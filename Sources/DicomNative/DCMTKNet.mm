#import "DCMTKNet.h"

#include "dcmtk/config/osconfig.h"
#include "dcmtk/dcmdata/dctk.h"
#include "dcmtk/dcmnet/scu.h"
#include "dcmtk/dcmnet/dstorscp.h"
#include "dcmtk/dcmnet/scpcfg.h"
#include "dcmtk/dcmtls/tlslayer.h"
#include "dcmtk/oflog/oflog.h"

#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/pem.h>

#include <thread>
#include <atomic>
#include <vector>
#include <string>
#include <memory>
#include <mutex>

// Transfer syntaxes we propose for every context.
static OFList<OFString> defaultTS() {
    OFList<OFString> ts;
    ts.push_back(UID_LittleEndianExplicitTransferSyntax);
    ts.push_back(UID_LittleEndianImplicitTransferSyntax);
    return ts;
}

// A representative set of storage SOP classes for SCP + C-GET role selection.
static const char *kStorageClasses[] = {
    UID_CTImageStorage, UID_MRImageStorage, UID_EnhancedCTImageStorage,
    UID_EnhancedMRImageStorage, UID_PositronEmissionTomographyImageStorage,
    UID_NuclearMedicineImageStorage, UID_UltrasoundImageStorage,
    UID_UltrasoundMultiframeImageStorage, UID_ComputedRadiographyImageStorage,
    UID_DigitalXRayImageStorageForPresentation, UID_DigitalMammographyXRayImageStorageForPresentation,
    UID_XRayAngiographicImageStorage, UID_SecondaryCaptureImageStorage,
    UID_MultiframeTrueColorSecondaryCaptureImageStorage, UID_RTImageStorage,
};

static NSDictionary *dsToDict(DcmItem *ds) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    DcmObject *obj = NULL;
    while ((obj = ds->nextInContainer(obj)) != NULL) {
        if (!obj->isLeaf()) continue;
        DcmElement *el = OFstatic_cast(DcmElement *, obj);
        if (el->getVR() == EVR_SQ) continue;
        DcmTag t = el->getTag();
        const char *kw = t.getTagName();
        if (!kw) continue;
        OFString v;
        if (el->getOFStringArray(v).good()) {
            out[[NSString stringWithUTF8String:kw]] =
                [NSString stringWithUTF8String:v.c_str()] ?: @"";
        }
    }
    return out;
}

// Subclass that can actually be stopped: DcmSCP polls these hooks between
// (and, in non-blocking mode, while idle waiting for) associations. Returning
// OFTrue makes listen() return so the socket is released — required to restart
// on the same port within one process.
class StoppableStorageSCP : public DcmStorageSCP {
    std::atomic<bool> stopFlag{false};
public:
    void requestStop() { stopFlag.store(true); }
    OFBool stopAfterCurrentAssociation() override { return stopFlag.load() ? OFTrue : OFFalse; }
    OFBool stopAfterConnectionTimeout() override { return stopFlag.load() ? OFTrue : OFFalse; }
};

// ---- SCP state ----
static std::thread *gSCPThread = nullptr;
static StoppableStorageSCP *gSCP = nullptr;
static std::atomic<bool> gSCPRunning{false};
static std::mutex gSCPMutex;   // guards the strings + port below (thread ↔ status)
static std::string gSCPAE, gSCPDir, gSCPError;
static int gSCPPort = 0;
static DcmTLSTransportLayer *gSCPTLS = nullptr;   // server TLS layer; outlives listen()

// Network timeout (seconds) applied to every outgoing SCU. <=0 disables (block
// forever — DCMTK default). Without this, any operation against a dead or
// firewalled host hangs indefinitely.
static std::atomic<int> gNetTimeout{15};

static void applyTimeouts(DcmSCU &scu) {
    int t = gNetTimeout.load();
    if (t <= 0) return;
    scu.setConnectionTimeout((Sint32)t);          // TCP connect
    scu.setACSETimeout((Uint32)t);                // association negotiation
    scu.setDIMSEBlockingMode(DIMSE_NONBLOCKING);  // make DIMSE receive respect…
    scu.setDIMSETimeout((Uint32)t);               // …this per-message timeout
}

// ---- TLS (outgoing SCU) ----
static std::atomic<bool> gTLSEnabled{false};
static std::atomic<bool> gTLSVerify{false};
static std::mutex gTLSMutex;
static std::string gTLSCAFile;   // guarded by gTLSMutex

/// Build a TLS layer per the global config. The caller attaches it with
/// scu.useSecureConnection() AFTER initNetwork() (DcmSCU requires the network
/// to exist first) and must keep it alive for the whole association
/// (useSecureConnection does NOT take ownership).
static std::unique_ptr<DcmTLSTransportLayer> makeTLSLayer(NSString **errOut) {
    if (!gTLSEnabled.load()) return nullptr;
    auto layer = std::make_unique<DcmTLSTransportLayer>(NET_REQUESTOR, /*randFile*/ nullptr,
                                                        /*initializeOpenSSL*/ OFTrue);
    OFCondition c = layer->setTLSProfile(TSP_Profile_BCP195);   // TLS 1.2+, modern ciphers
    if (c.bad()) { if (errOut) *errOut = @"TLS profile unsupported"; return nullptr; }
    if (gTLSVerify.load()) {
        layer->setCertificateVerification(DCV_requireCertificate);
        std::lock_guard<std::mutex> lock(gTLSMutex);
        if (!gTLSCAFile.empty() &&
            layer->addTrustedCertificateFile(gTLSCAFile.c_str(), DCF_Filetype_PEM).bad()) {
            if (errOut) *errOut = @"Could not load the trusted CA file";
            return nullptr;
        }
    } else {
        layer->setCertificateVerification(DCV_ignoreCertificate);
    }
    return layer;
}

// Generate a self-signed RSA server certificate (PEM). The built-in Storage SCP
// needs its own cert to accept a TLS association. Test-only; the peer chooses
// whether to verify it. Written once to a temp dir and reused.
static bool generateSelfSignedCert(const char *certPath, const char *keyPath) {
    EVP_PKEY *pkey = EVP_RSA_gen(2048);
    if (!pkey) return false;
    X509 *x509 = X509_new();
    if (!x509) { EVP_PKEY_free(pkey); return false; }
    ASN1_INTEGER_set(X509_get_serialNumber(x509), 1);
    X509_gmtime_adj(X509_getm_notBefore(x509), 0);
    X509_gmtime_adj(X509_getm_notAfter(x509), 60L * 60 * 24 * 3650);  // 10 years
    X509_set_pubkey(x509, pkey);
    X509_NAME *name = X509_get_subject_name(x509);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
                               (const unsigned char *)"DicomFlow Test SCP", -1, -1, 0);
    X509_set_issuer_name(x509, name);   // self-signed
    bool ok = X509_sign(x509, pkey, EVP_sha256()) != 0;
    if (ok) {
        FILE *kf = fopen(keyPath, "wb");
        ok = kf && PEM_write_PrivateKey(kf, pkey, nullptr, nullptr, 0, nullptr, nullptr);
        if (kf) fclose(kf);
        FILE *cf = fopen(certPath, "wb");
        ok = ok && cf && PEM_write_X509(cf, x509);
        if (cf) fclose(cf);
    }
    X509_free(x509);
    EVP_PKEY_free(pkey);
    return ok;
}

// A NET_ACCEPTOR TLS layer with a self-signed cert for the built-in SCP.
static DcmTLSTransportLayer *makeServerTLSLayer(std::string &err) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dicomflow-scp-tls"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *certPath = [dir stringByAppendingPathComponent:@"scp-cert.pem"];
    NSString *keyPath = [dir stringByAppendingPathComponent:@"scp-key.pem"];
    if (![fm fileExistsAtPath:certPath] || ![fm fileExistsAtPath:keyPath]) {
        if (!generateSelfSignedCert(certPath.fileSystemRepresentation, keyPath.fileSystemRepresentation)) {
            err = "could not generate a self-signed server certificate"; return nullptr;
        }
    }
    auto *layer = new DcmTLSTransportLayer(NET_ACCEPTOR, nullptr, OFTrue);
    if (layer->setTLSProfile(TSP_Profile_BCP195).bad()) { err = "TLS profile unsupported"; delete layer; return nullptr; }
    if (layer->setPrivateKeyFile(keyPath.fileSystemRepresentation, DCF_Filetype_PEM).bad()) {
        err = "could not load the server private key"; delete layer; return nullptr;
    }
    if (layer->setCertificateFile(certPath.fileSystemRepresentation, DCF_Filetype_PEM, TSP_Profile_BCP195).bad()) {
        err = "could not load the server certificate"; delete layer; return nullptr;
    }
    if (!layer->checkPrivateKeyMatchesCertificate()) { err = "server key/certificate mismatch"; delete layer; return nullptr; }
    layer->setCertificateVerification(DCV_ignoreCertificate);   // don't require a client cert
    return layer;
}

@implementation DCMTKNet

+ (BOOL)writeTestImageToPath:(NSString *)path {
    DcmFileFormat ff;
    DcmDataset *ds = ff.getDataset();
    char uid[100];
    ds->putAndInsertString(DCM_SOPClassUID, UID_SecondaryCaptureImageStorage);
    ds->putAndInsertString(DCM_SOPInstanceUID, dcmGenerateUniqueIdentifier(uid, SITE_INSTANCE_UID_ROOT));
    ds->putAndInsertString(DCM_StudyInstanceUID, dcmGenerateUniqueIdentifier(uid, SITE_STUDY_UID_ROOT));
    ds->putAndInsertString(DCM_SeriesInstanceUID, dcmGenerateUniqueIdentifier(uid, SITE_SERIES_UID_ROOT));
    ds->putAndInsertString(DCM_PatientName, "Test^SCP");
    ds->putAndInsertString(DCM_PatientID, "SCP-TEST");
    ds->putAndInsertString(DCM_Modality, "OT");
    ds->putAndInsertUint16(DCM_Rows, 2);
    ds->putAndInsertUint16(DCM_Columns, 2);
    ds->putAndInsertUint16(DCM_BitsAllocated, 8);
    ds->putAndInsertUint16(DCM_BitsStored, 8);
    ds->putAndInsertUint16(DCM_HighBit, 7);
    ds->putAndInsertUint16(DCM_PixelRepresentation, 0);
    ds->putAndInsertUint16(DCM_SamplesPerPixel, 1);
    ds->putAndInsertString(DCM_PhotometricInterpretation, "MONOCHROME2");
    const Uint8 px[4] = {0, 85, 170, 255};
    ds->putAndInsertUint8Array(DCM_PixelData, px, 4);
    return ff.saveFile(path.fileSystemRepresentation, EXS_LittleEndianExplicit).good() ? YES : NO;
}

+ (void)initialize {
    if (self == [DCMTKNet class]) {
        // Disable reverse-DNS lookups on connecting peers — otherwise DcmSCP
        // blocks for tens of seconds per association (classic DCMTK gotcha).
        dcmDisableGethostbyaddr.set(OFTrue);
    }
}

+ (void)enableVerboseLogging {
    OFLog::configure(OFLogger::DEBUG_LOG_LEVEL);
}

+ (void)setNetworkTimeout:(int)seconds {
    gNetTimeout = seconds;
}

+ (void)setTLSEnabled:(BOOL)enabled verifyPeer:(BOOL)verifyPeer caFile:(NSString *)caFile {
    gTLSEnabled = enabled;
    gTLSVerify = verifyPeer;
    std::lock_guard<std::mutex> lock(gTLSMutex);
    gTLSCAFile = caFile ? std::string(caFile.UTF8String) : std::string();
}

+ (NSDictionary *)echoToHost:(NSString *)host port:(int)port
                    calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE {
    DcmSCU scu;
    scu.setAETitle(callingAE.UTF8String);
    scu.setPeerAETitle(calledAE.UTF8String);
    scu.setPeerHostName(host.UTF8String);
    scu.setPeerPort((Uint16)port);
    scu.addPresentationContext(UID_VerificationSOPClass, defaultTS());

    applyTimeouts(scu);
    NSString *tlsErr = nil;
    auto tls = makeTLSLayer(&tlsErr);   // must outlive the association
    if (gTLSEnabled.load() && tls == nullptr)
        return @{@"success": @NO, @"message": tlsErr ?: @"TLS setup failed"};
    if (scu.initNetwork().bad())
        return @{@"success": @NO, @"message": @"Network init failed"};
    if (tls != nullptr && scu.useSecureConnection(tls.get()).bad())
        return @{@"success": @NO, @"message": @"Could not enable TLS on the connection"};
    if (scu.negotiateAssociation().bad()) {
        return @{@"success": @NO, @"message": @"Association failed"};
    }
    OFCondition cond = scu.sendECHORequest(0);
    NSArray *sop = scu.isConnected() ? @[@"Verification SOP Class"] : @[];
    scu.releaseAssociation();
    return @{@"success": @(cond.good()),
             @"echoStatus": @(cond.good() ? 0 : -1),
             @"message": [NSString stringWithUTF8String:cond.text()],
             @"sopClasses": sop};
}

+ (NSDictionary *)storeFiles:(NSArray<NSString *> *)paths
                      toHost:(NSString *)host port:(int)port
                    calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE {
    DcmSCU scu;
    scu.setAETitle(callingAE.UTF8String);
    scu.setPeerAETitle(calledAE.UTF8String);
    scu.setPeerHostName(host.UTF8String);
    scu.setPeerPort((Uint16)port);

    // Add a context per unique SOP class found in the files.
    NSMutableSet *added = [NSMutableSet set];
    for (NSString *p in paths) {
        DcmFileFormat ff;
        if (ff.loadFile(p.fileSystemRepresentation).bad()) continue;
        OFString sop;
        if (ff.getDataset()->findAndGetOFString(DCM_SOPClassUID, sop).good() && !sop.empty()) {
            NSString *s = [NSString stringWithUTF8String:sop.c_str()];
            if (![added containsObject:s]) {
                [added addObject:s];
                scu.addPresentationContext(sop, defaultTS());
            }
        }
    }
    if (added.count == 0) return @{@"success": @NO, @"message": @"no storable files"};
    applyTimeouts(scu);
    NSString *tlsErr = nil;
    auto tls = makeTLSLayer(&tlsErr);   // must outlive the association
    if (gTLSEnabled.load() && tls == nullptr)
        return @{@"success": @NO, @"message": tlsErr ?: @"TLS setup failed"};
    if (scu.initNetwork().bad())
        return @{@"success": @NO, @"message": @"Network init failed"};
    if (tls != nullptr && scu.useSecureConnection(tls.get()).bad())
        return @{@"success": @NO, @"message": @"Could not enable TLS on the connection"};
    if (scu.negotiateAssociation().bad()) {
        return @{@"success": @NO, @"message": @"Association failed"};
    }

    int sent = 0, total = 0;
    for (NSString *p in paths) {
        DcmFileFormat ff;
        if (ff.loadFile(p.fileSystemRepresentation).bad()) continue;
        total++;
        DcmDataset *ds = ff.getDataset();
        DcmXfer xfer(ds->getOriginalXfer());
        if (xfer.isEncapsulated())
            ds->chooseRepresentation(EXS_LittleEndianExplicit, NULL);
        OFString sop;
        ds->findAndGetOFString(DCM_SOPClassUID, sop);
        T_ASC_PresentationContextID pid =
            scu.findPresentationContextID(sop, UID_LittleEndianExplicitTransferSyntax);
        if (pid == 0)
            pid = scu.findPresentationContextID(sop, UID_LittleEndianImplicitTransferSyntax);
        if (pid == 0) continue;
        Uint16 rsp = 0;
        if (scu.sendSTORERequest(pid, OFFilename(), ds, rsp).good() && rsp == 0) sent++;
    }
    scu.releaseAssociation();
    return @{@"success": @(total > 0 && sent == total), @"sent": @(sent), @"total": @(total),
             @"message": [NSString stringWithFormat:@"Sent %d of %d", sent, total]};
}

+ (NSDictionary *)queryHost:(NSString *)host port:(int)port
                   calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE
                      level:(NSString *)level
                    filters:(NSDictionary<NSString *, NSString *> *)filters {
    DcmSCU scu;
    scu.setAETitle(callingAE.UTF8String);
    scu.setPeerAETitle(calledAE.UTF8String);
    scu.setPeerHostName(host.UTF8String);
    scu.setPeerPort((Uint16)port);
    scu.addPresentationContext(UID_FINDStudyRootQueryRetrieveInformationModel, defaultTS());
    applyTimeouts(scu);
    NSString *tlsErr = nil;
    auto tls = makeTLSLayer(&tlsErr);   // must outlive the association
    if (gTLSEnabled.load() && tls == nullptr)
        return @{@"success": @NO, @"message": tlsErr ?: @"TLS setup failed"};
    if (scu.initNetwork().bad())
        return @{@"success": @NO, @"message": @"Network init failed"};
    if (tls != nullptr && scu.useSecureConnection(tls.get()).bad())
        return @{@"success": @NO, @"message": @"Could not enable TLS on the connection"};
    if (scu.negotiateAssociation().bad())
        return @{@"success": @NO, @"message": @"Association failed"};

    T_ASC_PresentationContextID pid =
        scu.findPresentationContextID(UID_FINDStudyRootQueryRetrieveInformationModel, "");
    if (pid == 0) {
        scu.releaseAssociation();
        return @{@"success": @NO, @"message":
            @"Peer accepted the association but not the Study Root FIND presentation context."};
    }
    DcmDataset query;
    query.putAndInsertString(DCM_QueryRetrieveLevel, level.UTF8String);
    for (NSString *k in filters) {
        DcmTag tag;
        if (DcmTag::findTagFromName(k.UTF8String, tag).good())
            query.putAndInsertString(tag.getXTag(), filters[k].UTF8String);
    }
    // C-FIND only returns attributes present in the query — add the standard
    // return keys for the level (universal match) unless already used as filters.
    {
        static const DcmTagKey studyKeys[] = {
            DCM_PatientName, DCM_PatientID, DCM_StudyDate, DCM_StudyDescription,
            DCM_ModalitiesInStudy, DCM_NumberOfStudyRelatedSeries, DCM_StudyInstanceUID};
        static const DcmTagKey seriesKeys[] = {
            DCM_SeriesInstanceUID, DCM_SeriesNumber, DCM_SeriesDescription,
            DCM_Modality, DCM_NumberOfSeriesRelatedInstances, DCM_StudyInstanceUID};
        static const DcmTagKey imageKeys[] = {
            DCM_SOPInstanceUID, DCM_SOPClassUID, DCM_InstanceNumber};
        const DcmTagKey *keys = studyKeys; size_t n = sizeof(studyKeys) / sizeof(*studyKeys);
        if ([level isEqualToString:@"SERIES"]) { keys = seriesKeys; n = sizeof(seriesKeys) / sizeof(*seriesKeys); }
        else if ([level isEqualToString:@"IMAGE"]) { keys = imageKeys; n = sizeof(imageKeys) / sizeof(*imageKeys); }
        for (size_t i = 0; i < n; i++)
            if (!query.tagExists(keys[i])) query.insertEmptyElement(keys[i]);
    }

    OFList<QRResponse *> responses;
    OFCondition cond = scu.sendFINDRequest(pid, &query, &responses);
    NSMutableArray *results = [NSMutableArray array];
    for (auto *r : responses) {
        if (r && r->m_dataset) [results addObject:dsToDict(r->m_dataset)];
        delete r;   // DcmSCU hands ownership of each response to the caller.
    }
    scu.releaseAssociation();
    return @{@"success": @(cond.good()), @"count": @((int)results.count), @"results": results,
             @"message": [NSString stringWithUTF8String:cond.text()]};
}

// Flatten an MWL response: top-level leaves + the first Scheduled Procedure Step item.
static NSDictionary *mwlItemToDict(DcmItem *ds) {
    NSMutableDictionary *out = [dsToDict(ds) mutableCopy];
    DcmSequenceOfItems *sq = NULL;
    if (ds->findAndGetSequence(DCM_ScheduledProcedureStepSequence, sq).good()
        && sq != NULL && sq->card() > 0) {
        if (DcmItem *item = sq->getItem(0)) {
            [out addEntriesFromDictionary:dsToDict(item)];
        }
    }
    return out;
}

+ (NSDictionary *)worklistQueryHost:(NSString *)host port:(int)port
                           calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE
                            filters:(NSDictionary<NSString *, NSString *> *)filters {
    DcmSCU scu;
    scu.setAETitle(callingAE.UTF8String);
    scu.setPeerAETitle(calledAE.UTF8String);
    scu.setPeerHostName(host.UTF8String);
    scu.setPeerPort((Uint16)port);
    scu.addPresentationContext(UID_FINDModalityWorklistInformationModel, defaultTS());
    applyTimeouts(scu);
    NSString *tlsErr = nil;
    auto tls = makeTLSLayer(&tlsErr);   // must outlive the association
    if (gTLSEnabled.load() && tls == nullptr)
        return @{@"success": @NO, @"message": tlsErr ?: @"TLS setup failed"};
    if (scu.initNetwork().bad())
        return @{@"success": @NO, @"message": @"Network init failed"};
    if (tls != nullptr && scu.useSecureConnection(tls.get()).bad())
        return @{@"success": @NO, @"message": @"Could not enable TLS on the connection"};
    if (scu.negotiateAssociation().bad())
        return @{@"success": @NO, @"message":
            @"Peer did not accept Modality Worklist (MWL FIND) — is a worklist service enabled on it?"};

    T_ASC_PresentationContextID pid =
        scu.findPresentationContextID(UID_FINDModalityWorklistInformationModel, "");
    if (pid == 0) {
        scu.releaseAssociation();
        return @{@"success": @NO, @"message":
            @"Peer accepted the association but not the MWL FIND presentation context."};
    }

    DcmDataset query;
    // Universal-match (empty) return keys at the top level.
    query.insertEmptyElement(DCM_PatientName);
    query.insertEmptyElement(DCM_PatientID);
    query.insertEmptyElement(DCM_AccessionNumber);
    query.insertEmptyElement(DCM_StudyInstanceUID);
    query.insertEmptyElement(DCM_RequestedProcedureDescription);
    query.insertEmptyElement(DCM_RequestedProcedureID);
    query.insertEmptyElement(DCM_ReferringPhysicianName);

    // Scheduled Procedure Step Sequence item with its return/matching keys.
    DcmItem *sps = NULL;
    query.findOrCreateSequenceItem(DCM_ScheduledProcedureStepSequence, sps, 0);
    if (sps) {
        sps->insertEmptyElement(DCM_Modality);
        sps->insertEmptyElement(DCM_ScheduledStationAETitle);
        sps->insertEmptyElement(DCM_ScheduledProcedureStepStartDate);
        sps->insertEmptyElement(DCM_ScheduledProcedureStepStartTime);
        sps->insertEmptyElement(DCM_ScheduledPerformingPhysicianName);
        sps->insertEmptyElement(DCM_ScheduledProcedureStepDescription);
    }

    for (NSString *k in filters) {
        NSString *val = filters[k];
        if (val.length == 0) continue;
        if ([k isEqualToString:@"Modality"] && sps)
            sps->putAndInsertString(DCM_Modality, val.UTF8String);
        else if ([k isEqualToString:@"ScheduledStationAETitle"] && sps)
            sps->putAndInsertString(DCM_ScheduledStationAETitle, val.UTF8String);
        else if ([k isEqualToString:@"ScheduledProcedureStepStartDate"] && sps)
            sps->putAndInsertString(DCM_ScheduledProcedureStepStartDate, val.UTF8String);
        else {
            DcmTag tag;
            if (DcmTag::findTagFromName(k.UTF8String, tag).good())
                query.putAndInsertString(tag.getXTag(), val.UTF8String);
        }
    }

    OFList<QRResponse *> responses;
    OFCondition cond = scu.sendFINDRequest(pid, &query, &responses);
    NSMutableArray *results = [NSMutableArray array];
    for (auto *r : responses) {
        if (r && r->m_dataset) [results addObject:mwlItemToDict(r->m_dataset)];
        delete r;   // caller owns each response.
    }
    scu.releaseAssociation();
    return @{@"success": @(cond.good()), @"count": @((int)results.count), @"results": results,
             @"message": [NSString stringWithUTF8String:cond.text()]};
}

+ (NSDictionary *)retrieveFromHost:(NSString *)host port:(int)port
                          calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE
                             level:(NSString *)level
                              keys:(NSDictionary<NSString *, NSString *> *)keys
                            method:(NSString *)method
                          moveDest:(NSString *)moveDest
                         outputDir:(NSString *)outputDir {
    BOOL isGet = [method isEqualToString:@"get"];
    DcmSCU scu;
    scu.setAETitle(callingAE.UTF8String);
    scu.setPeerAETitle(calledAE.UTF8String);
    scu.setPeerHostName(host.UTF8String);
    scu.setPeerPort((Uint16)port);

    const char *model = isGet ? UID_GETStudyRootQueryRetrieveInformationModel
                              : UID_MOVEStudyRootQueryRetrieveInformationModel;
    scu.addPresentationContext(model, defaultTS());
    if (isGet) {
        [[NSFileManager defaultManager] createDirectoryAtPath:outputDir
            withIntermediateDirectories:YES attributes:nil error:nil];
        scu.setStorageMode(DCMSCU_STORAGE_DISK);
        scu.setStorageDir(outputDir.fileSystemRepresentation);
        for (size_t i = 0; i < sizeof(kStorageClasses) / sizeof(char *); i++)
            scu.addPresentationContext(kStorageClasses[i], defaultTS(), ASC_SC_ROLE_SCP);
    }
    applyTimeouts(scu);
    NSString *tlsErr = nil;
    auto tls = makeTLSLayer(&tlsErr);   // must outlive the association
    if (gTLSEnabled.load() && tls == nullptr)
        return @{@"success": @NO, @"message": tlsErr ?: @"TLS setup failed"};
    if (scu.initNetwork().bad())
        return @{@"success": @NO, @"message": @"Network init failed"};
    if (tls != nullptr && scu.useSecureConnection(tls.get()).bad())
        return @{@"success": @NO, @"message": @"Could not enable TLS on the connection"};
    if (scu.negotiateAssociation().bad())
        return @{@"success": @NO, @"message": @"Association failed"};

    T_ASC_PresentationContextID pid = scu.findPresentationContextID(model, "");
    if (pid == 0) {
        scu.releaseAssociation();
        return @{@"success": @NO, @"message":
            @"Peer accepted the association but not the retrieve presentation context."};
    }
    DcmDataset q;
    q.putAndInsertString(DCM_QueryRetrieveLevel, level.UTF8String);
    for (NSString *k in keys) {
        DcmTag tag;
        if (DcmTag::findTagFromName(k.UTF8String, tag).good())
            q.putAndInsertString(tag.getXTag(), keys[k].UTF8String);
    }

    int before = (int)[[[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:outputDir error:nil] count];
    OFList<RetrieveResponse *> responses;
    OFCondition cond;
    if (isGet) cond = scu.sendCGETRequest(pid, &q, &responses);
    else cond = scu.sendMOVERequest(pid, (moveDest ?: @"DICOMBENCH").UTF8String, &q, &responses);

    // For C-MOVE the objects go to the destination AE, not our disk — read the
    // completed-suboperation count from the final response instead.
    int moved = 0;
    for (auto *r : responses) {
        if (r) moved = r->m_numberOfCompletedSubops;
        delete r;   // caller owns each response.
    }
    scu.releaseAssociation();

    int after = (int)[[[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:outputDir error:nil] count];
    return @{@"success": @(cond.good()),
             @"received": @(isGet ? (after - before) : moved),
             @"receivedDir": outputDir,
             @"message": [NSString stringWithUTF8String:cond.text()]};
}

// ---- Negotiation probe ----

+ (NSDictionary *)probeContextsHost:(NSString *)host port:(int)port
                           calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE {
    // Transfer syntaxes to probe (uncompressed + common compressed).
    static const char *kProbeTS[] = {
        UID_LittleEndianExplicitTransferSyntax,
        UID_LittleEndianImplicitTransferSyntax,
        UID_DeflatedExplicitVRLittleEndianTransferSyntax,
        UID_JPEGProcess1TransferSyntax,          // JPEG Baseline (lossy 8-bit)
        UID_JPEGProcess14SV1TransferSyntax,      // JPEG Lossless
        UID_JPEG2000LosslessOnlyTransferSyntax,
        UID_JPEG2000TransferSyntax,
        UID_RLELosslessTransferSyntax,
    };
    const size_t nTS = sizeof(kProbeTS) / sizeof(char *);

    // SOP classes: Verification + up to 14 storage classes (15 × 8 = 120 contexts,
    // under the 128-per-association limit).
    std::vector<const char *> sops;
    sops.push_back(UID_VerificationSOPClass);
    const size_t nStorage = sizeof(kStorageClasses) / sizeof(char *);
    for (size_t i = 0; i < nStorage && i < 14; i++) sops.push_back(kStorageClasses[i]);

    DcmSCU scu;
    scu.setAETitle(callingAE.UTF8String);
    scu.setPeerAETitle(calledAE.UTF8String);
    scu.setPeerHostName(host.UTF8String);
    scu.setPeerPort((Uint16)port);

    // One presentation context per (SOP, TS) so each pair negotiates
    // independently — DICOM accepts a single TS per context.
    size_t proposed = 0;
    for (const char *sop : sops)
        for (size_t j = 0; j < nTS; j++) {
            OFList<OFString> one; one.push_back(kProbeTS[j]);
            if (scu.addPresentationContext(sop, one).good()) proposed++;
        }

    applyTimeouts(scu);
    NSString *tlsErr = nil;
    auto tls = makeTLSLayer(&tlsErr);   // must outlive the association
    if (gTLSEnabled.load() && tls == nullptr)
        return @{@"success": @NO, @"message": tlsErr ?: @"TLS setup failed"};
    if (scu.initNetwork().bad())
        return @{@"success": @NO, @"message": @"Network init failed"};
    if (tls != nullptr && scu.useSecureConnection(tls.get()).bad())
        return @{@"success": @NO, @"message": @"Could not enable TLS on the connection"};
    OFCondition neg = scu.negotiateAssociation();
    if (neg.bad())
        return @{@"success": @NO, @"message": [NSString stringWithUTF8String:neg.text()]};

    NSMutableArray *results = [NSMutableArray array];
    NSUInteger acceptedContexts = 0;
    for (const char *sop : sops) {
        NSMutableArray *tsNames = [NSMutableArray array];
        for (size_t j = 0; j < nTS; j++) {
            if (scu.findPresentationContextID(sop, kProbeTS[j]) != 0) {
                const char *tn = dcmFindNameOfUID(kProbeTS[j]);
                [tsNames addObject:(tn ? @(tn) : @(kProbeTS[j]))];
                acceptedContexts++;
            }
        }
        const char *sn = dcmFindNameOfUID(sop);
        [results addObject:@{
            @"sopClass": @(sop),
            @"sopName": sn ? @(sn) : @(sop),
            @"accepted": @(tsNames.count > 0),
            @"transferSyntaxes": tsNames,
        }];
    }
    scu.releaseAssociation();
    return @{@"success": @YES,
             @"message": [NSString stringWithFormat:@"%lu of %lu contexts accepted",
                          (unsigned long)acceptedContexts, (unsigned long)proposed],
             @"results": results};
}

// ---- Storage SCP ----

+ (NSDictionary *)startSCPWithAETitle:(NSString *)ae port:(int)port outputDir:(NSString *)dir
                      enforceCalledAE:(BOOL)enforceCalledAE {
    if (gSCPRunning.load()) {
        std::lock_guard<std::mutex> lock(gSCPMutex);
        return @{@"running": @YES, @"aeTitle": @(gSCPAE.c_str()),
                 @"port": @(gSCPPort), @"message": @"already running"};
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
        withIntermediateDirectories:YES attributes:nil error:nil];

    gSCP = new StoppableStorageSCP();
    gSCP->setAETitle(ae.UTF8String);
    // enforce: refuse associations whose Called AE != ours. Permissive (default
    // DcmSCP): respond with (accept) whatever Called AE the peer used.
    gSCP->setRespondWithCalledAETitle(enforceCalledAE ? OFFalse : OFTrue);
    gSCP->setPort((Uint16)port);
    gSCP->setOutputDirectory(dir.fileSystemRepresentation);
    // Non-blocking accept with a 1 s poll: listen() wakes periodically and checks
    // the stop hooks, so stopSCP can make it return and release the socket
    // (otherwise a blocking accept holds the port until the process exits →
    // "Address already in use" on the next start).
    gSCP->setConnectionBlockingMode(DUL_NOBLOCK);
    gSCP->setConnectionTimeout(1);

    // Configure accepted contexts via a generated association config file
    // (the canonical DcmStorageSCP setup).
    NSMutableString *cfg = [NSMutableString string];
    [cfg appendString:@"[[TransferSyntaxes]]\n[Uncompressed]\n"];
    [cfg appendFormat:@"TransferSyntax1 = %s\n", UID_LittleEndianExplicitTransferSyntax];
    [cfg appendFormat:@"TransferSyntax2 = %s\n\n", UID_LittleEndianImplicitTransferSyntax];
    [cfg appendString:@"[[PresentationContexts]]\n[StorageSCP]\n"];
    [cfg appendFormat:@"PresentationContext1 = %s\\Uncompressed\n", UID_VerificationSOPClass];
    for (size_t i = 0; i < sizeof(kStorageClasses) / sizeof(char *); i++)
        [cfg appendFormat:@"PresentationContext%zu = %s\\Uncompressed\n",
            i + 2, kStorageClasses[i]];
    [cfg appendString:@"\n[[Profiles]]\n[Default]\nPresentationContexts = StorageSCP\n"];

    NSString *cfgPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dicomflow_scp.cfg"];
    [cfg writeToFile:cfgPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    OFCondition lc = gSCP->loadAssociationCfgFile(cfgPath.fileSystemRepresentation);
    OFCondition prof = gSCP->setAndCheckAssociationProfile("Default");

    // With global DIMSE-TLS on, the SCP must also speak TLS or a C-MOVE-to-self
    // can't deliver (the SCU side is encrypted). Attach a server TLS layer
    // (self-signed cert). Must be set before listen() and outlive it.
    if (gTLSEnabled.load()) {
        std::string terr;
        gSCPTLS = makeServerTLSLayer(terr);
        if (gSCPTLS == nullptr) {
            delete gSCP; gSCP = nullptr;
            return @{@"running": @NO,
                     @"message": [NSString stringWithFormat:@"SCP TLS setup failed: %s", terr.c_str()]};
        }
        gSCP->getConfig().setTransportLayer(gSCPTLS);
    }

    {
        std::lock_guard<std::mutex> lock(gSCPMutex);
        gSCPError = std::string("load=") + lc.text() + " profile=" + prof.text()
                  + (gTLSEnabled.load() ? " tls=on" : "");
        gSCPAE = ae.UTF8String;
        gSCPDir = dir.UTF8String;
        gSCPPort = port;
    }
    gSCPRunning.store(true);
    gSCPThread = new std::thread([] {
        if (gSCP) {
            OFCondition c = gSCP->listen();
            // A requested stop returns these — not an error. Anything else
            // (e.g. bind "Address already in use") means we never really ran.
            if (c.bad() && c != NET_EC_StopAfterConnectionTimeout && c != NET_EC_StopAfterAssociation) {
                std::lock_guard<std::mutex> lock(gSCPMutex);
                gSCPError += std::string(" listen=") + c.text();
                gSCPRunning.store(false);
            }
        }
    });
    return @{@"running": @YES, @"aeTitle": ae, @"port": @(port)};
}

+ (NSDictionary *)stopSCP {
    if (gSCPRunning.load() && gSCP) {
        gSCP->requestStop();
        // Join: the NOBLOCK listen returns within the 1 s connection timeout (or
        // after the current association finishes), cleanly closing the socket so
        // a later start can rebind the same port. Runs off the main thread
        // (DicomEngine.scpStop is async).
        if (gSCPThread && gSCPThread->joinable()) gSCPThread->join();
        delete gSCPThread; gSCPThread = nullptr;
        delete gSCP; gSCP = nullptr;
        delete gSCPTLS; gSCPTLS = nullptr;   // safe now that listen() has returned
        gSCPRunning.store(false);
    }
    return @{@"running": @NO};
}

+ (NSDictionary *)scpStatus {
    std::lock_guard<std::mutex> lock(gSCPMutex);
    return @{@"running": @(gSCPRunning.load()),
             @"aeTitle": @(gSCPAE.c_str()),
             @"port": @(gSCPPort),
             @"receivedDir": @(gSCPDir.c_str()),
             @"error": @(gSCPError.c_str())};
}

+ (NSArray<NSDictionary *> *)scpReceivedFrom:(NSString *)dir {
    NSMutableArray *items = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:dir error:nil] ?: @[];
    for (NSString *name in files) {
        NSString *path = [dir stringByAppendingPathComponent:name];
        DcmFileFormat ff;
        if (ff.loadFile(path.fileSystemRepresentation).bad()) continue;
        DcmDataset *ds = ff.getDataset();
        OFString pn, mod, ser, sop;
        ds->findAndGetOFString(DCM_PatientName, pn);
        ds->findAndGetOFString(DCM_Modality, mod);
        ds->findAndGetOFString(DCM_SeriesInstanceUID, ser);
        ds->findAndGetOFString(DCM_SOPInstanceUID, sop);
        [items addObject:@{
            @"path": path,
            @"patient": @(pn.c_str()), @"modality": @(mod.c_str()),
            @"seriesUID": @(ser.c_str()), @"sopUID": @(sop.c_str()),
            @"studyUID": @"",
        }];
    }
    return items;
}

@end
