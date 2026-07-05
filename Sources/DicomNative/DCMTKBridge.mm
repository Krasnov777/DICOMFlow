#import "DCMTKBridge.h"

#include "dcmtk/config/osconfig.h"
#include "dcmtk/dcmdata/dctk.h"
#include "dcmtk/dcmdata/dcuid.h"
#include "dcmtk/dcmjpeg/djdecode.h"
#include "dcmtk/dcmjpls/djdecode.h"
#include "dcmtk/dcmdata/dcrledrg.h"
#include "fmjpeg2k/djdecode.h"   // JPEG 2000 (fmjpeg2koj + OpenJPEG)
#include "dcmtk/dcmsr/dsrdoc.h"
#include "dcmtk/dcmdata/dcdicdir.h"       // DICOMDIR (media directory) reader
#include "dcmtk/dcmimgle/dcmimage.h"      // DicomImage: windowed 8-bit rendering
#include "dcmtk/dcmimage/diregist.h"      // registers color-image support
#include "dcmtk/ofstd/ofstream.h"
#include "dcmtk/dcmiod/iodcommn.h"        // common-IOD module aggregator
#include "dcmtk/dcmiod/modgeneralimage.h" // General Image module (image IODs)
#include "dcmtk/dcmiod/iodrules.h"        // IODRule / IODRules rule engine

#include <map>
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#include <sstream>

static BOOL isPixelGeometryKeyword(NSString *kw) {
    static NSSet *s = [NSSet setWithArray:@[
        @"Rows", @"Columns", @"BitsAllocated", @"BitsStored", @"HighBit",
        @"PixelRepresentation", @"SamplesPerPixel", @"PhotometricInterpretation",
        @"PixelData", @"NumberOfFrames"]];
    return [s containsObject:kw];
}

static OFBool resolveTag(const char *keyword, DcmTagKey &outKey) {
    DcmTag tag;
    if (DcmTag::findTagFromName(keyword, tag).good()) {
        outKey = tag.getXTag();
        return OFTrue;
    }
    return OFFalse;
}

static OFString mapUID(std::map<std::string, std::string> &m, const OFString &in) {
    std::string k(in.c_str());
    auto it = m.find(k);
    if (it != m.end()) return OFString(it->second.c_str());
    char newuid[100];
    dcmGenerateUniqueIdentifier(newuid, SITE_INSTANCE_UID_ROOT);
    m[k] = newuid;
    return OFString(newuid);
}

@implementation DCMTKBridge

+ (void)registerCodecs {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DJDecoderRegistration::registerCodecs();        // JPEG (lossy + lossless)
        DJLSDecoderRegistration::registerCodecs();      // JPEG-LS
        DcmRLEDecoderRegistration::registerCodecs();    // RLE
        FMJPEG2KDecoderRegistration::registerCodecs();  // JPEG 2000 (OpenJPEG)
    });
}

static double getF64(DcmDataset *ds, const DcmTagKey &key, double dflt) {
    Float64 v = 0;
    return ds->findAndGetFloat64(key, v).good() ? (double)v : dflt;
}

+ (NSDictionary *)decodeFile:(NSString *)path error:(NSError **)error {
    [self registerCodecs];

    DcmFileFormat ff;
    OFCondition status = ff.loadFile([path fileSystemRepresentation]);
    if (status.bad()) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:1
            userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithUTF8String:status.text()]}];
        return nil;
    }
    DcmDataset *ds = ff.getDataset();

    // Decompress encapsulated transfer syntaxes to native little-endian.
    DcmXfer xfer(ds->getOriginalXfer());
    if (xfer.isEncapsulated()) {
        if (ds->chooseRepresentation(EXS_LittleEndianExplicit, NULL).bad()) {
            if (error) *error = [NSError errorWithDomain:@"DCMTK" code:2
                userInfo:@{NSLocalizedDescriptionKey:@"could not decompress pixel data (unsupported codec, e.g. JPEG2000)"}];
            return nil;
        }
    }

    Uint16 rows = 0, cols = 0, bitsAlloc = 0, pixelRep = 0;
    ds->findAndGetUint16(DCM_Rows, rows);
    ds->findAndGetUint16(DCM_Columns, cols);
    ds->findAndGetUint16(DCM_BitsAllocated, bitsAlloc);
    ds->findAndGetUint16(DCM_PixelRepresentation, pixelRep);
    if (rows == 0 || cols == 0) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:3
            userInfo:@{NSLocalizedDescriptionKey:@"no image dimensions"}];
        return nil;
    }
    if (bitsAlloc != 16 && bitsAlloc != 8) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:4
            userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"unsupported BitsAllocated=%u (8/16-bit supported)", bitsAlloc]}];
        return nil;
    }

    Uint16 samples = 1, planar = 0;
    ds->findAndGetUint16(DCM_SamplesPerPixel, samples);
    ds->findAndGetUint16(DCM_PlanarConfiguration, planar);
    // Uncompressed YBR (e.g. YBR_FULL US clips) needs YBR→RGB; compressed color is
    // already RGB after chooseRepresentation() above.
    OFString photo;
    ds->findAndGetOFString(DCM_PhotometricInterpretation, photo);
    BOOL isYBR = (photo.substr(0, 3) == "YBR");

    unsigned long perFrame = (unsigned long)rows * cols;
    NSData *pixelData = nil;
    NSData *rgbData = nil;          // interleaved RGB8 (all frames) when color
    BOOL isColor = NO;
    unsigned long frames = 1;

    if (bitsAlloc == 16) {
        const Uint16 *pix = NULL;
        unsigned long count = 0;
        if (ds->findAndGetUint16Array(DCM_PixelData, pix, &count).bad() || pix == NULL) {
            if (error) *error = [NSError errorWithDomain:@"DCMTK" code:5
                userInfo:@{NSLocalizedDescriptionKey:@"no pixel data"}];
            return nil;
        }
        if (count < perFrame) {
            if (error) *error = [NSError errorWithDomain:@"DCMTK" code:6
                userInfo:@{NSLocalizedDescriptionKey:@"pixel data smaller than one frame"}];
            return nil;
        }
        // All frames (multi-frame US clips / enhanced CT-MR become a stack).
        // Bit pattern of Uint16 == Sint16 two's complement → raw copy is exact.
        frames = count / perFrame;
        pixelData = [NSData dataWithBytes:pix length:perFrame * frames * sizeof(int16_t)];
    } else {
        // 8-bit: widen grayscale to int16, or reduce interleaved/planar color
        // (RGB after codec decompression) to luma — keeps the int16 grayscale
        // pipeline (Metal texture, HU probe, window/level) unchanged.
        const Uint8 *pix8 = NULL;
        unsigned long count8 = 0;
        if (ds->findAndGetUint8Array(DCM_PixelData, pix8, &count8).bad() || pix8 == NULL) {
            if (error) *error = [NSError errorWithDomain:@"DCMTK" code:5
                userInfo:@{NSLocalizedDescriptionKey:@"no pixel data"}];
            return nil;
        }
        if (samples != 1 && samples != 3) {
            if (error) *error = [NSError errorWithDomain:@"DCMTK" code:4
                userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"unsupported SamplesPerPixel=%u", samples]}];
            return nil;
        }
        if (count8 < perFrame * samples) {
            if (error) *error = [NSError errorWithDomain:@"DCMTK" code:6
                userInfo:@{NSLocalizedDescriptionKey:@"pixel data smaller than one frame"}];
            return nil;
        }
        frames = count8 / (perFrame * samples);
        NSMutableData *buf = [NSMutableData dataWithLength:perFrame * frames * sizeof(int16_t)];
        int16_t *out = (int16_t *)buf.mutableBytes;
        NSMutableData *rgbBuf = (samples == 3) ? [NSMutableData dataWithLength:perFrame * frames * 3] : nil;
        Uint8 *rgbOut = (Uint8 *)rgbBuf.mutableBytes;
        auto clamp8 = [](double v) -> Uint8 { return (Uint8)(v < 0 ? 0 : (v > 255 ? 255 : v)); };
        for (unsigned long f = 0; f < frames; f++) {
            const Uint8 *src = pix8 + f * perFrame * samples;
            int16_t *dst = out + f * perFrame;
            if (samples == 1) {
                if (pixelRep == 1) {                   // signed 8-bit (rare)
                    const int8_t *s = (const int8_t *)src;
                    for (unsigned long i = 0; i < perFrame; i++) dst[i] = s[i];
                } else {
                    for (unsigned long i = 0; i < perFrame; i++) dst[i] = src[i];
                }
            } else {                                   // 3-sample color → RGB8 + luma
                isColor = YES;
                Uint8 *rgb = rgbOut + f * perFrame * 3;
                for (unsigned long i = 0; i < perFrame; i++) {
                    unsigned c0, c1, c2;                 // sample components
                    if (planar == 1) { c0 = src[i]; c1 = src[perFrame + i]; c2 = src[2 * perFrame + i]; }
                    else { c0 = src[3 * i]; c1 = src[3 * i + 1]; c2 = src[3 * i + 2]; }
                    Uint8 R, G, B;
                    if (isYBR) {                         // YBR_FULL → RGB (Y,Cb,Cr)
                        double Y = c0, Cb = (double)c1 - 128, Cr = (double)c2 - 128;
                        R = clamp8(Y + 1.402 * Cr);
                        G = clamp8(Y - 0.344136 * Cb - 0.714136 * Cr);
                        B = clamp8(Y + 1.772 * Cb);
                        dst[i] = (int16_t)c0;            // luma = Y
                    } else {
                        R = (Uint8)c0; G = (Uint8)c1; B = (Uint8)c2;
                        dst[i] = (int16_t)((299u * R + 587u * G + 114u * B) / 1000);
                    }
                    rgb[3 * i] = R; rgb[3 * i + 1] = G; rgb[3 * i + 2] = B;
                }
            }
        }
        pixelData = buf;
        rgbData = rgbBuf;
    }

    OFString modality, seriesUID, sopUID;
    ds->findAndGetOFString(DCM_Modality, modality);
    ds->findAndGetOFString(DCM_SeriesInstanceUID, seriesUID);
    ds->findAndGetOFString(DCM_SOPInstanceUID, sopUID);

    auto f64arr = ^NSArray *(const DcmTagKey &key, int n, double dflt) {
        NSMutableArray *a = [NSMutableArray arrayWithCapacity:n];
        for (int i = 0; i < n; i++) {
            Float64 v = dflt;
            ds->findAndGetFloat64(key, v, i);
            [a addObject:@(v)];
        }
        return a;
    };

    // 8-bit data gets full-range window defaults; 16-bit keeps CT-ish ones.
    double defWC = bitsAlloc == 8 ? 128.0 : 40.0;
    double defWW = bitsAlloc == 8 ? 256.0 : 400.0;
    NSMutableDictionary *result = [@{
        @"pixelData": pixelData,
        @"rows": @(rows),
        @"columns": @(cols),
        @"bitsAllocated": @(bitsAlloc),
        @"pixelRepresentation": @(pixelRep),
        @"samplesPerPixel": @(samples),
        @"frames": @(frames),
        @"isColorConvertedToGray": @(isColor),
        @"slope": @(getF64(ds, DCM_RescaleSlope, 1.0)),
        @"intercept": @(getF64(ds, DCM_RescaleIntercept, 0.0)),
        @"windowCenter": @(getF64(ds, DCM_WindowCenter, defWC)),
        @"windowWidth": @(getF64(ds, DCM_WindowWidth, defWW)),
        @"sliceThickness": @(getF64(ds, DCM_SliceThickness, 1.0)),
        @"position": f64arr(DCM_ImagePositionPatient, 3, 0.0),
        @"orientation": f64arr(DCM_ImageOrientationPatient, 6, 0.0),
        @"pixelSpacing": f64arr(DCM_PixelSpacing, 2, 1.0),
        @"modality": modality.c_str() ? [NSString stringWithUTF8String:modality.c_str()] : @"",
        @"seriesUID": seriesUID.c_str() ? [NSString stringWithUTF8String:seriesUID.c_str()] : @"",
        @"sopUID": sopUID.c_str() ? [NSString stringWithUTF8String:sopUID.c_str()] : @"",
    } mutableCopy];
    if (rgbData) result[@"rgb"] = rgbData;   // interleaved RGB8, all frames
    return result;
}

+ (NSString *)stringForElement:(DcmElement *)elem {
    DcmEVR evr = elem->getVR();
    if (evr == EVR_SQ) {
        return @"<Sequence>";
    }
    // Binary / large VRs: don't dump bytes.
    if (evr == EVR_OB || evr == EVR_OW || evr == EVR_OD || evr == EVR_OF ||
        evr == EVR_OL || evr == EVR_UN || evr == EVR_px || evr == EVR_ox) {
        return [NSString stringWithFormat:@"<Binary: %lu bytes>",
                (unsigned long)elem->getLength()];
    }
    OFString val;
    if (elem->getOFStringArray(val).good()) {
        return [NSString stringWithUTF8String:val.c_str()] ?: @"";
    }
    return @"";
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)readTags:(NSString *)path
                                                       error:(NSError **)error {
    DcmFileFormat ff;
    OFCondition status = ff.loadFile([path fileSystemRepresentation]);
    if (status.bad()) {
        if (error) {
            *error = [NSError errorWithDomain:@"DCMTK" code:1
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithUTF8String:status.text()]}];
        }
        return nil;
    }

    DcmDataset *ds = ff.getDataset();
    NSMutableArray *out = [NSMutableArray array];
    DcmStack stack;
    while (ds->nextObject(stack, OFTrue).good()) {
        DcmObject *obj = stack.top();
        if (!obj->isLeaf() && obj->getVR() != EVR_SQ) continue;
        DcmElement *elem = OFstatic_cast(DcmElement *, obj);
        DcmTag tag = elem->getTag();

        NSString *tagStr = [NSString stringWithFormat:@"(%04X,%04X)",
                            tag.getGroup(), tag.getElement()];
        const char *name = tag.getTagName();
        const char *vr = tag.getVR().getVRName();

        [out addObject:@{
            @"tag": tagStr,
            @"keyword": name ? [NSString stringWithUTF8String:name] : @"",
            @"name": name ? [NSString stringWithUTF8String:name] : @"Unknown",
            @"vr": vr ? [NSString stringWithUTF8String:vr] : @"",
            @"value": [self stringForElement:elem],
        }];
    }
    return out;
}

+ (NSDictionary *)editTags:(NSString *)path
                     edits:(NSArray<NSDictionary *> *)edits
                outputPath:(NSString *)outputPath
                     error:(NSError **)error {
    DcmFileFormat ff;
    if (ff.loadFile([path fileSystemRepresentation]).bad()) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"could not read DICOM file"}];
        return nil;
    }
    DcmDataset *ds = ff.getDataset();
    NSMutableArray *applied = [NSMutableArray array];
    NSMutableArray *skipped = [NSMutableArray array];

    for (NSDictionary *op in edits) {
        NSString *kw = op[@"keyword"];
        id val = op[@"value"];
        if (isPixelGeometryKeyword(kw)) {
            [skipped addObject:@{@"keyword": kw, @"reason": @"pixel-geometry tag (blocked)"}];
            continue;
        }
        DcmTagKey key;
        if (!resolveTag(kw.UTF8String, key)) {
            [skipped addObject:@{@"keyword": kw, @"reason": @"unknown keyword"}];
            continue;
        }
        if (val == nil || [val isKindOfClass:[NSNull class]]) {
            ds->findAndDeleteElement(key);
            [applied addObject:@{@"keyword": kw, @"value": @"<deleted>"}];
        } else {
            NSString *sval = (NSString *)val;
            if (ds->putAndInsertString(key, sval.UTF8String).good()) {
                [applied addObject:@{@"keyword": kw, @"value": sval}];
            } else {
                [skipped addObject:@{@"keyword": kw, @"reason": @"could not set value"}];
            }
        }
    }

    OFCondition s = ff.saveFile([outputPath fileSystemRepresentation], ds->getOriginalXfer());
    if (s.bad()) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:2
            userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithUTF8String:s.text()]}];
        return nil;
    }
    return @{@"outputPath": outputPath, @"applied": applied, @"skipped": skipped};
}

+ (NSDictionary *)anonymize:(NSArray<NSString *> *)paths
                  outputDir:(NSString *)outputDir
                    profile:(NSDictionary *)profile
                      error:(NSError **)error {
    [[NSFileManager defaultManager] createDirectoryAtPath:outputDir
        withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *repName = profile[@"replacePatientName"];
    NSString *repID = profile[@"replacePatientID"];
    BOOL clearDates = [profile[@"clearDates"] boolValue];
    BOOL clearIdent = [profile[@"clearIdentifiers"] boolValue];
    BOOL rmPrivate = [profile[@"removePrivateTags"] boolValue];
    BOOL regenUIDs = [profile[@"regenerateUIDs"] boolValue];
    // PS3.15 Basic Profile mode + its retain/clean options.
    BOOL basicProfile = [profile[@"basicProfile"] boolValue];
    BOOL retainDates = [profile[@"retainDates"] boolValue];
    BOOL retainDevice = [profile[@"retainDeviceIdentity"] boolValue];
    BOOL retainPatientChars = [profile[@"retainPatientChars"] boolValue];
    BOOL cleanDescriptors = [profile[@"cleanDescriptors"] boolValue];

    static NSArray *dateKw = @[@"StudyDate", @"SeriesDate", @"AcquisitionDate",
        @"ContentDate", @"PatientBirthDate", @"StudyTime", @"SeriesTime",
        @"AcquisitionTime", @"ContentTime"];
    static NSArray *identKw = @[@"InstitutionName", @"InstitutionAddress",
        @"ReferringPhysicianName", @"PerformingPhysicianName", @"OperatorsName",
        @"PatientAddress", @"PatientTelephoneNumbers", @"OtherPatientIDs",
        @"OtherPatientNames", @"StationName"];

    // --- PS3.15 Annex E Basic Application Level Confidentiality Profile (curated
    // core of Table E.1-1). X = remove, Z = zero; option lists are removed unless
    // the corresponding "retain" option is set. ---
    static NSArray *bpRemove = @[
        @"OtherPatientIDs", @"OtherPatientNames", @"OtherPatientIDsSequence",
        @"PatientAddress", @"PatientTelephoneNumbers", @"PatientMotherBirthName",
        @"MilitaryRank", @"BranchOfService", @"MedicalRecordLocator", @"EthnicGroup",
        @"Occupation", @"AdditionalPatientHistory", @"PatientComments", @"PatientBirthName",
        @"PatientReligiousPreference", @"ResponsiblePerson", @"ResponsibleOrganization",
        @"CountryOfResidence", @"RegionOfResidence", @"PatientInsurancePlanCodeSequence",
        @"PatientPrimaryLanguageCodeSequence", @"ReferringPhysicianAddress",
        @"ReferringPhysicianTelephoneNumbers", @"PhysiciansOfRecord",
        @"PerformingPhysicianName", @"NameOfPhysiciansReadingStudy", @"OperatorsName",
        @"RequestingPhysician", @"ScheduledPerformingPhysicianName", @"InstitutionName",
        @"InstitutionAddress", @"InstitutionalDepartmentName", @"OrderCallbackPhoneNumber",
        @"OrderEnteredBy", @"IssuerOfPatientID", @"AdmissionID", @"CurrentPatientLocation",
        @"PatientState", @"ReferencedPatientSequence", @"AdmittingDiagnosesDescription"];
    static NSArray *bpZero = @[
        @"AccessionNumber", @"StudyID", @"ReferringPhysicianName", @"PatientBirthDate"];
    static NSArray *bpDevice = @[
        @"StationName", @"DeviceSerialNumber", @"DetectorID", @"GantryID", @"PlateID",
        @"CassetteID", @"PerformedStationAETitle", @"PerformedStationName",
        @"ScheduledStationName", @"ScheduledStationAETitle", @"PerformedLocation"];
    static NSArray *bpDates = @[
        @"StudyDate", @"SeriesDate", @"AcquisitionDate", @"ContentDate", @"OverlayDate",
        @"AcquisitionDateTime", @"StudyTime", @"SeriesTime", @"AcquisitionTime",
        @"ContentTime", @"OverlayTime", @"InstanceCreationDate", @"InstanceCreationTime",
        @"PatientBirthTime", @"AdmittingDate", @"AdmittingTime",
        @"ScheduledProcedureStepStartDate", @"ScheduledProcedureStepStartTime",
        @"PerformedProcedureStepStartDate", @"PerformedProcedureStepStartTime"];
    static NSArray *bpPatientChar = @[
        @"PatientSex", @"PatientAge", @"PatientSize", @"PatientWeight",
        @"PregnancyStatus", @"SmokingStatus", @"MedicalAlerts", @"Allergies",
        @"LastMenstrualDate"];
    static NSArray *bpDescriptors = @[
        @"StudyDescription", @"SeriesDescription", @"ImageComments", @"DerivationDescription",
        @"ProtocolName", @"PerformedProcedureStepDescription", @"RequestedProcedureDescription",
        @"ContentDescription"];

    std::map<std::string, std::string> uidMap;
    NSMutableArray *warnings = [NSMutableArray array];
    int processed = 0;

    for (NSString *path in paths) {
        DcmFileFormat ff;
        if (ff.loadFile([path fileSystemRepresentation]).bad()) continue;
        DcmDataset *ds = ff.getDataset();

        if (regenUIDs) {
            DcmStack stack;
            while (ds->nextObject(stack, OFTrue).good()) {
                DcmObject *o = stack.top();
                if (o->getVR() != EVR_UI) continue;
                DcmTag ot = o->getTag();
                const char *nm = ot.getTagName();
                if (nm && strcmp(nm, "SOPClassUID") == 0) continue;
                DcmElement *el = OFstatic_cast(DcmElement *, o);
                OFString v;
                if (el->getOFString(v, 0).good() && !v.empty()) {
                    el->putString(mapUID(uidMap, v).c_str());
                }
            }
            // Keep file-meta SOP Instance UID in sync.
            OFString sop;
            if (ds->findAndGetOFString(DCM_SOPInstanceUID, sop).good() && !sop.empty()) {
                ff.getMetaInfo()->putAndInsertString(DCM_MediaStorageSOPInstanceUID, sop.c_str());
            }
        }

        if (repName && ![repName isKindOfClass:[NSNull class]])
            ds->putAndInsertString(DCM_PatientName, repName.UTF8String);
        if (repID && ![repID isKindOfClass:[NSNull class]])
            ds->putAndInsertString(DCM_PatientID, repID.UTF8String);

        if (clearDates) {
            for (NSString *kw in dateKw) {
                DcmTagKey key;
                if (resolveTag(kw.UTF8String, key)) ds->putAndInsertString(key, "");
            }
        }
        if (clearIdent) {
            for (NSString *kw in identKw) {
                DcmTagKey key;
                if (resolveTag(kw.UTF8String, key)) ds->findAndDeleteElement(key);
            }
        }
        if (rmPrivate) {
            for (long i = (long)ds->card() - 1; i >= 0; i--) {
                DcmElement *el = ds->getElement((unsigned long)i);
                if (el && (el->getGTag() & 1)) {
                    DcmObject *r = ds->remove((unsigned long)i);
                    delete r;
                }
            }
        }

        if (basicProfile) {
            auto delKw = [&](NSArray *arr) {
                for (NSString *kw in arr) { DcmTagKey k; if (resolveTag(kw.UTF8String, k)) ds->findAndDeleteElement(k); }
            };
            auto zeroKw = [&](NSArray *arr) {
                for (NSString *kw in arr) { DcmTagKey k; if (resolveTag(kw.UTF8String, k)) ds->putAndInsertString(k, ""); }
            };
            delKw(bpRemove);
            zeroKw(bpZero);
            if (!retainDevice)        delKw(bpDevice);
            if (!retainDates)         zeroKw(bpDates);
            if (!retainPatientChars)  delKw(bpPatientChar);
            if (cleanDescriptors)     zeroKw(bpDescriptors);
            // PS3.15 de-identification metadata.
            ds->putAndInsertString(DCM_PatientIdentityRemoved, "YES");
            ds->putAndInsertString(DCM_DeidentificationMethod, "DicomFlow PS3.15 Basic Profile");
        }

        NSString *out = [outputDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"anon_%05d.dcm", processed]];
        if (ff.saveFile([out fileSystemRepresentation], ds->getOriginalXfer()).good()) {
            processed++;
        } else {
            [warnings addObject:[NSString stringWithFormat:@"failed: %@", path.lastPathComponent]];
        }
    }

    if (processed == 0) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:3
            userInfo:@{NSLocalizedDescriptionKey:@"no DICOM files could be anonymized"}];
        return nil;
    }
    return @{@"processed": @(processed), @"uidsRemapped": @((int)uidMap.size()),
             @"warnings": warnings};
}

+ (NSArray<NSDictionary *> *)scanSeries:(NSString *)directory {
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:directory isDirectory:&isDir] && isDir) {
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:directory];
        for (NSString *rel in en) {
            if ([rel.lastPathComponent.lowercaseString isEqualToString:@"dicomdir"]) continue;
            [files addObject:[directory stringByAppendingPathComponent:rel]];
        }
    } else {
        [files addObject:directory];
    }

    // seriesUID -> mutable info dict (with a files array)
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];

    for (NSString *path in files) {
        DcmFileFormat ff;
        // Stop before pixel data for speed.
        if (ff.loadFileUntilTag(path.fileSystemRepresentation, EXS_Unknown, EGL_noChange,
                                DCM_MaxReadLength, ERM_autoDetect, DCM_PixelData).bad()) continue;
        DcmDataset *ds = ff.getDataset();
        OFString suid;
        if (ds->findAndGetOFString(DCM_SeriesInstanceUID, suid).bad() || suid.empty()) continue;
        NSString *key = [NSString stringWithUTF8String:suid.c_str()];

        NSMutableDictionary *g = groups[key];
        if (!g) {
            OFString desc, mod, num, pn, sdesc;
            ds->findAndGetOFString(DCM_SeriesDescription, desc);
            ds->findAndGetOFString(DCM_Modality, mod);
            ds->findAndGetOFString(DCM_SeriesNumber, num);
            ds->findAndGetOFString(DCM_PatientName, pn);
            ds->findAndGetOFString(DCM_StudyDescription, sdesc);
            g = [@{
                @"seriesUID": key,
                @"description": @(desc.c_str()),
                @"modality": @(mod.c_str()),
                @"seriesNumber": @(num.c_str()),
                @"patient": @(pn.c_str()),
                @"studyDescription": @(sdesc.c_str()),
                @"files": [NSMutableArray array],
            } mutableCopy];
            groups[key] = g;
            [order addObject:key];
        }
        [(NSMutableArray *)g[@"files"] addObject:path];
    }

    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSString *key in order) {
        // Sort each series' files for stable ordering.
        NSMutableDictionary *g = groups[key];
        [(NSMutableArray *)g[@"files"] sortUsingSelector:@selector(compare:)];
        [out addObject:g];
    }
    return out;
}

+ (NSString *)transferSyntaxName:(NSString *)path {
    DcmFileFormat ff;
    if (ff.loadFile([path fileSystemRepresentation]).bad()) return nil;
    E_TransferSyntax xfer = ff.getDataset()->getOriginalXfer();
    DcmXfer x(xfer);
    const char *n = x.getXferName();
    return n ? [NSString stringWithUTF8String:n] : nil;
}

static BOOL isValidUID(NSString *uid) {
    if (uid.length == 0 || uid.length > 64) return NO;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet];
    if ([uid rangeOfCharacterFromSet:bad].location != NSNotFound) return NO;
    if ([uid hasPrefix:@"."] || [uid hasSuffix:@"."] || [uid containsString:@".."]) return NO;
    return YES;
}

// Check every unconditional type-1/2 attribute of a dcmiod module against the
// dataset, using DCMTK's own IOD rule engine. Appends one row per attribute and
// counts type-1 violations (which make the file non-conformant).
static void collectModuleRules(IODComponent &module, DcmItem *ds, NSMutableArray *out, int *type1Errors) {
    OFshared_ptr<IODRules> rules = module.getRules();
    if (!rules) return;
    for (IODRules::iterator it = rules->begin(); it != rules->end(); ++it) {
        IODRule *rule = it->second;
        if (rule == NULL) continue;
        OFString type = rule->getType();
        if (!(type == "1" || type == "2")) continue;   // skip 1C/2C/3 (conditional/optional)
        // Frame of Reference is IOD-conditional (spatial IODs like CT/MR require
        // it, SC/PDF/SR do not); DCMTK bundles it with General Series. We can't
        // tell per-SOP-class here, so don't enforce it (avoids false positives).
        if (rule->getModule() == "FrameOfReferenceModule") continue;
        DcmTagKey key = rule->getTagKey();
        OFCondition rc = rule->check(*ds, OFTrue);
        DcmTag tag(key);
        [out addObject:@{
            @"module": @(rule->getModule().c_str()),
            @"tag": @(key.toString().c_str()),
            @"name": tag.getTagName() ? @(tag.getTagName()) : @"",
            @"type": @(type.c_str()),
            @"ok": @(rc.good()),
            @"message": rc.good() ? @"" : @(rc.text()),
        }];
        if (rc.bad() && type == "1") (*type1Errors)++;
    }
}

+ (NSDictionary *)validateFile:(NSString *)path {
    NSMutableArray *errors = [NSMutableArray array];
    NSMutableArray *warnings = [NSMutableArray array];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];

    DcmFileFormat ff;
    OFCondition c = ff.loadFile([path fileSystemRepresentation]);
    if (c.bad()) {
        [errors addObject:[NSString stringWithFormat:@"Cannot read as DICOM: %s", c.text()]];
        return @{@"ok": @NO, @"errors": errors, @"warnings": warnings, @"info": info};
    }
    DcmDataset *ds = ff.getDataset();
    DcmMetaInfo *meta = ff.getMetaInfo();

    DcmXfer xfer(ds->getOriginalXfer());
    if (xfer.getXferName()) info[@"transferSyntax"] = @(xfer.getXferName());

    OFString metaSOP;
    if (meta == NULL || meta->card() == 0) {
        [warnings addObject:@"No file meta information (group 0002) — not a Part-10 file."];
    } else {
        meta->findAndGetOFString(DCM_MediaStorageSOPClassUID, metaSOP);
        OFString metaTS; meta->findAndGetOFString(DCM_TransferSyntaxUID, metaTS);
        if (metaTS.empty()) [warnings addObject:@"Meta: missing TransferSyntaxUID (0002,0010)."];
    }

    auto checkUID = [&](const DcmTagKey &tag, NSString *name, bool required) -> NSString * {
        OFString v; ds->findAndGetOFString(tag, v);
        NSString *val = [NSString stringWithUTF8String:v.c_str()] ?: @"";
        if (val.length == 0) {
            [required ? errors : warnings addObject:[NSString stringWithFormat:@"Missing %@%@.", required ? @"required " : @"", name]];
        } else if (!isValidUID(val)) {
            [errors addObject:[NSString stringWithFormat:@"Invalid UID for %@: '%@'.", name, val]];
        }
        return val;
    };
    NSString *sopClassUID = checkUID(DCM_SOPClassUID, @"SOP Class UID (0008,0016)", true);
    checkUID(DCM_SOPInstanceUID, @"SOP Instance UID (0008,0018)", true);
    checkUID(DCM_StudyInstanceUID, @"Study Instance UID (0020,000D)", true);
    checkUID(DCM_SeriesInstanceUID, @"Series Instance UID (0020,000E)", true);

    if (sopClassUID.length) {
        const char *name = dcmFindNameOfUID(sopClassUID.UTF8String);
        info[@"sopClass"] = name ? @(name) : @"(unknown SOP class)";
        info[@"sopClassUID"] = sopClassUID;
        if (metaSOP.length() > 0 && strcmp(metaSOP.c_str(), sopClassUID.UTF8String) != 0)
            [warnings addObject:@"MediaStorageSOPClassUID (meta) differs from SOPClassUID (dataset)."];
    }

    { OFString m; ds->findAndGetOFString(DCM_Modality, m); if (!m.empty()) info[@"modality"] = @(m.c_str()); }

    // ---- IOD conformance via DCMTK's dcmiod rule engine ----
    // Authoritative per-module type-1/2 checks for the common composite modules
    // (Patient, Patient Study, General Study/Series/Equipment, SOP Common) plus
    // the General Image module for image objects. Each attribute is checked
    // against its standard rule (present, non-empty for type-1, VM/VR).
    NSMutableArray *iodModules = [NSMutableArray array];
    int iodType1Errors = 0;
    DcmIODCommon iodCommon;
    collectModuleRules(iodCommon.getPatient(), ds, iodModules, &iodType1Errors);
    collectModuleRules(iodCommon.getPatientStudy(), ds, iodModules, &iodType1Errors);
    collectModuleRules(iodCommon.getStudy(), ds, iodModules, &iodType1Errors);
    collectModuleRules(iodCommon.getSeries(), ds, iodModules, &iodType1Errors);
    collectModuleRules(iodCommon.getEquipment(), ds, iodModules, &iodType1Errors);
    collectModuleRules(iodCommon.getSOPCommon(), ds, iodModules, &iodType1Errors);

    // Image Pixel type-1 (only when Pixel Data is present — General Image adds the
    // rest via the rule engine above/below).
    if (ds->tagExists(DCM_PixelData)) {
        IODGeneralImageModule iodImage;
        collectModuleRules(iodImage, ds, iodModules, &iodType1Errors);
        const struct { DcmTagKey tag; const char *name; } imgT1[] = {
            {DCM_Rows, "Rows (0028,0010)"}, {DCM_Columns, "Columns (0028,0011)"},
            {DCM_BitsAllocated, "Bits Allocated (0028,0100)"}, {DCM_BitsStored, "Bits Stored (0028,0101)"},
            {DCM_HighBit, "High Bit (0028,0102)"}, {DCM_PixelRepresentation, "Pixel Representation (0028,0103)"},
            {DCM_SamplesPerPixel, "Samples per Pixel (0028,0002)"},
            {DCM_PhotometricInterpretation, "Photometric Interpretation (0028,0004)"},
        };
        for (auto &n : imgT1)
            if (!ds->tagExists(n.tag))
                [errors addObject:[NSString stringWithFormat:@"Pixel Data present but missing type-1 %s.", n.name]];
    }

    // Per-element VR / value verification (capped).
    int bad = 0;
    DcmStack stack;
    while (ds->nextObject(stack, OFTrue).good() && bad < 60) {
        DcmObject *obj = stack.top();
        if (obj == NULL || !obj->isLeaf()) continue;
        DcmElement *el = OFstatic_cast(DcmElement *, obj);
        OFCondition vc = el->verify(OFFalse);
        if (vc.bad()) {
            DcmTag t = el->getTag();
            [warnings addObject:[NSString stringWithFormat:@"%s %s: %s",
                t.getXTag().toString().c_str(), t.getTagName() ? t.getTagName() : "", vc.text()]];
            bad++;
        }
    }

    return @{@"ok": @(errors.count == 0 && iodType1Errors == 0),
             @"errors": errors, @"warnings": warnings, @"info": info,
             @"iodModules": iodModules};
}

+ (NSString *)readReportText:(NSString *)path error:(NSError **)error {
    DcmFileFormat ff;
    OFCondition c = ff.loadFile([path fileSystemRepresentation]);
    if (c.bad()) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:1
            userInfo:@{NSLocalizedDescriptionKey: @(c.text())}];
        return nil;
    }
    DSRDocument doc;
    // Relax DCMTK's strict content/relationship validation so we can render
    // real-world SRs (e.g. X-Ray/CT Radiation Dose SR) that trip the default
    // checks — accept unknown relationships, ignore constraint + item errors,
    // and skip any content item that still won't parse.
    const size_t readFlags = DSRTypes::RF_acceptUnknownRelationshipType
                           | DSRTypes::RF_ignoreRelationshipConstraints
                           | DSRTypes::RF_ignoreContentItemErrors
                           | DSRTypes::RF_skipInvalidContentItems;
    c = doc.read(*ff.getDataset(), readFlags);
    if (c.bad()) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:2
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Not a readable Structured Report: %s", c.text()]}];
        return nil;
    }
    OFStringStream os;
    if (doc.print(os, DSRTypes::PF_printItemPosition).bad()) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:3
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to render the report."}];
        return nil;
    }
    OFSTRINGSTREAM_GETOFSTRING(os, text)
    // SR text is often Latin-1, not UTF-8 → fall back so we never return nil.
    NSString *s = [NSString stringWithUTF8String:text.c_str()];
    if (s == nil) {
        s = [[NSString alloc] initWithBytes:text.c_str()
                                     length:text.length()
                                   encoding:NSISOLatin1StringEncoding];
    }
    if (s == nil) {
        if (error) *error = [NSError errorWithDomain:@"DCMTK" code:4
            userInfo:@{NSLocalizedDescriptionKey: @"Report text could not be decoded."}];
    }
    return s;
}

+ (NSDictionary *)renderDisplay8:(NSString *)path {
    DicomImage di([path fileSystemRepresentation]);
    if (di.getStatus() != EIS_Normal) return nil;
    if (di.isMonochrome()) di.setMinMaxWindow();     // ensure a visible window
    const int cols = (int)di.getWidth(), rows = (int)di.getHeight();
    const int samples = di.isMonochrome() ? 1 : 3;
    const void *data = di.getOutputData(8 /*bits*/, 0 /*frame*/, 0 /*planar (interleaved)*/);
    if (data == NULL || cols <= 0 || rows <= 0) return nil;
    NSData *buf = [NSData dataWithBytes:data length:(NSUInteger)cols * rows * samples];
    return @{ @"data": buf, @"rows": @(rows), @"columns": @(cols), @"samples": @(samples) };
}

+ (NSDictionary *)redactFile:(NSString *)path
                       rects:(NSArray<NSArray<NSNumber *> *> *)rects
                  outputPath:(NSString *)outputPath {
    DcmFileFormat ff;
    if (ff.loadFile([path fileSystemRepresentation]).bad())
        return @{@"success": @NO, @"message": @"Cannot read the file as DICOM."};
    DcmDataset *ds = ff.getDataset();
    // Redaction needs raw pixels — decompress if the file is encoded.
    if (ds->chooseRepresentation(EXS_LittleEndianExplicit, NULL).bad())
        return @{@"success": @NO, @"message": @"Could not decode the pixel data."};

    Uint16 rows = 0, cols = 0, samples = 1, bitsAlloc = 16;
    ds->findAndGetUint16(DCM_Rows, rows);
    ds->findAndGetUint16(DCM_Columns, cols);
    ds->findAndGetUint16(DCM_SamplesPerPixel, samples);
    ds->findAndGetUint16(DCM_BitsAllocated, bitsAlloc);
    if (rows == 0 || cols == 0) return @{@"success": @NO, @"message": @"No image pixels."};
    OFString framesStr; long frames = 1;
    if (ds->findAndGetOFString(DCM_NumberOfFrames, framesStr).good() && !framesStr.empty())
        frames = std::max(1L, atol(framesStr.c_str()));
    const size_t frameLen = (size_t)rows * cols * samples;

    // Pixel-space rects (top-left origin), clamped.
    struct Rect { int x0, y0, x1, y1; };
    std::vector<Rect> px;
    for (NSArray<NSNumber *> *r in rects) {
        if (r.count < 4) continue;
        int x0 = (int)floor(r[0].doubleValue * cols), y0 = (int)floor(r[1].doubleValue * rows);
        int x1 = (int)ceil((r[0].doubleValue + r[2].doubleValue) * cols);
        int y1 = (int)ceil((r[1].doubleValue + r[3].doubleValue) * rows);
        x0 = std::max(0, std::min(x0, (int)cols)); x1 = std::max(0, std::min(x1, (int)cols));
        y0 = std::max(0, std::min(y0, (int)rows)); y1 = std::max(0, std::min(y1, (int)rows));
        if (x1 > x0 && y1 > y0) px.push_back({x0, y0, x1, y1});
    }
    if (px.empty()) return @{@"success": @NO, @"message": @"No regions to redact."};

    auto zeroRegions = [&](auto *buf, size_t count) {
        for (long f = 0; f < frames; f++) {
            size_t base = (size_t)f * frameLen;
            if (base + frameLen > count) break;
            for (const Rect &rc : px)
                for (int y = rc.y0; y < rc.y1; y++)
                    for (int x = rc.x0; x < rc.x1; x++) {
                        size_t p = base + ((size_t)y * cols + x) * samples;
                        for (int s = 0; s < samples; s++) buf[p + s] = 0;
                    }
        }
    };

    if (bitsAlloc <= 8) {
        const Uint8 *src = NULL; unsigned long count = 0;
        if (ds->findAndGetUint8Array(DCM_PixelData, src, &count).bad())
            return @{@"success": @NO, @"message": @"Could not access 8-bit pixel data."};
        std::vector<Uint8> buf(src, src + count);
        zeroRegions(buf.data(), buf.size());
        ds->putAndInsertUint8Array(DCM_PixelData, buf.data(), (unsigned long)buf.size());
    } else {
        const Uint16 *src = NULL; unsigned long count = 0;
        if (ds->findAndGetUint16Array(DCM_PixelData, src, &count).bad())
            return @{@"success": @NO, @"message": @"Could not access 16-bit pixel data."};
        std::vector<Uint16> buf(src, src + count);
        zeroRegions(buf.data(), buf.size());
        ds->putAndInsertUint16Array(DCM_PixelData, buf.data(), (unsigned long)count);
    }
    ds->putAndInsertString(DCM_BurnedInAnnotation, "NO");

    if (ff.saveFile([outputPath fileSystemRepresentation], EXS_LittleEndianExplicit).bad())
        return @{@"success": @NO, @"message": @"Could not write the redacted file."};
    return @{@"success": @YES,
             @"message": [NSString stringWithFormat:@"Redacted %lu region(s) across %ld frame(s)",
                          (unsigned long)px.size(), frames]};
}

+ (nullable NSString *)dumpFile:(NSString *)path {
    DcmFileFormat ff;
    if (ff.loadFile([path fileSystemRepresentation]).bad()) return nil;
    std::ostringstream oss;
    // PF_shortenLongTagValues keeps Pixel Data et al. from dumping megabytes.
    ff.print(oss, DCMTypes::PF_shortenLongTagValues);
    return [NSString stringWithUTF8String:oss.str().c_str()] ?: @"";
}

+ (NSDictionary *)readDicomDir:(NSString *)path {
    auto S = [](const OFString &s) -> NSString * { return [NSString stringWithUTF8String:s.c_str()] ?: @""; };
    // DcmDicomDir silently creates an empty directory for a non-DICOMDIR file, so
    // verify the media SOP class first for an honest rejection.
    {
        DcmFileFormat probe;
        if (probe.loadFile([path fileSystemRepresentation]).bad())
            return @{@"success": @NO, @"message": @"Cannot read the file as DICOM."};
        OFString mediaSOP;
        if (probe.getMetaInfo() == NULL ||
            probe.getMetaInfo()->findAndGetOFString(DCM_MediaStorageSOPClassUID, mediaSOP).bad() ||
            mediaSOP != UID_MediaStorageDirectoryStorage)
            return @{@"success": @NO, @"message": @"Not a DICOMDIR (wrong Media Storage SOP Class)."};
    }
    DcmDicomDir dicomdir([path fileSystemRepresentation]);
    OFCondition status = dicomdir.error();
    if (status.bad())
        return @{@"success": @NO, @"message": [NSString stringWithFormat:@"Not a DICOMDIR: %s", status.text()]};

    NSString *baseDir = [path stringByDeletingLastPathComponent];
    DcmDirectoryRecord *root = &dicomdir.getRootRecord();
    NSMutableArray *patients = [NSMutableArray array];

    DcmDirectoryRecord *pRec = NULL;
    while ((pRec = root->nextSub(pRec)) != NULL) {
        if (pRec->getRecordType() != ERT_Patient) continue;
        OFString pName, pID;
        pRec->findAndGetOFString(DCM_PatientName, pName);
        pRec->findAndGetOFString(DCM_PatientID, pID);
        NSMutableArray *studies = [NSMutableArray array];

        DcmDirectoryRecord *stRec = NULL;
        while ((stRec = pRec->nextSub(stRec)) != NULL) {
            if (stRec->getRecordType() != ERT_Study) continue;
            OFString stUID, stDate, stDesc;
            stRec->findAndGetOFString(DCM_StudyInstanceUID, stUID);
            stRec->findAndGetOFString(DCM_StudyDate, stDate);
            stRec->findAndGetOFString(DCM_StudyDescription, stDesc);
            NSMutableArray *seriesArr = [NSMutableArray array];

            DcmDirectoryRecord *seRec = NULL;
            while ((seRec = stRec->nextSub(seRec)) != NULL) {
                if (seRec->getRecordType() != ERT_Series) continue;
                OFString seUID, modality, seNum, seDesc;
                seRec->findAndGetOFString(DCM_SeriesInstanceUID, seUID);
                seRec->findAndGetOFString(DCM_Modality, modality);
                seRec->findAndGetOFString(DCM_SeriesNumber, seNum);
                seRec->findAndGetOFString(DCM_SeriesDescription, seDesc);
                NSMutableArray *files = [NSMutableArray array];

                DcmDirectoryRecord *imRec = NULL;
                while ((imRec = seRec->nextSub(imRec)) != NULL) {
                    OFString fileID;
                    if (imRec->findAndGetOFStringArray(DCM_ReferencedFileID, fileID).good() && !fileID.empty()) {
                        // ReferencedFileID (0004,1500) is a multi-valued path; on
                        // media the components are separated by backslash.
                        NSString *rel = [S(fileID) stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
                        [files addObject:[baseDir stringByAppendingPathComponent:rel]];
                    }
                }
                [seriesArr addObject:@{ @"uid": S(seUID), @"modality": S(modality),
                                        @"number": S(seNum), @"description": S(seDesc), @"files": files }];
            }
            [studies addObject:@{ @"uid": S(stUID), @"date": S(stDate),
                                  @"description": S(stDesc), @"series": seriesArr }];
        }
        [patients addObject:@{ @"name": S(pName), @"patientID": S(pID), @"studies": studies }];
    }
    return @{@"success": @YES, @"baseDir": baseDir, @"patients": patients,
             @"message": [NSString stringWithFormat:@"%lu patient(s)", (unsigned long)patients.count]};
}

// A deterministic pattern value in [0,1] at normalized voxel (fx,fy,fz) ∈ [0,1].
static float patternValue(const std::string &pat, float fx, float fy, float fz,
                          int x, int y, int z) {
    if (pat == "gradient") return fx;
    if (pat == "solid") return 0.7f;
    if (pat == "checkerboard") return (((x / 16) + (y / 16) + (z / 8)) & 1) ? 0.85f : 0.1f;
    if (pat == "rings") {
        float dx = fx - 0.5f, dy = fy - 0.5f;
        float r = sqrtf(dx * dx + dy * dy) * 2.0f;              // 0 at center, 1 at edge
        return 0.5f + 0.5f * sinf(r * 18.0f);
    }
    if (pat == "noise") {
        uint32_t h = (uint32_t)(x * 73856093) ^ (uint32_t)(y * 19349663) ^ (uint32_t)(z * 83492791);
        h = (h ^ (h >> 13)) * 1274126177u;
        return (float)(h & 0xFFFF) / 65535.0f;
    }
    // default: a filled sphere phantom (nice in 2D/MPR/3D)
    float dx = fx - 0.5f, dy = fy - 0.5f, dz = fz - 0.5f;
    float d = sqrtf(dx * dx + dy * dy + dz * dz);
    return d < 0.4f ? (1.0f - d / 0.4f) : 0.0f;                 // bright core, fades to edge
}

+ (NSDictionary *)generateDatasetToDir:(NSString *)dir
                              sopClass:(NSString *)sopClass
                                  rows:(int)rows columns:(int)columns
                                slices:(int)slices pattern:(NSString *)pattern {
    rows = std::max(8, std::min(rows, 2048));
    columns = std::max(8, std::min(columns, 2048));
    slices = std::max(1, std::min(slices, 1024));
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    const char *sop = sopClass.UTF8String;
    const bool isCT = strcmp(sop, UID_CTImageStorage) == 0;
    const bool isMR = strcmp(sop, UID_MRImageStorage) == 0;
    const bool bits16 = isCT || isMR;                 // volume modalities → 16-bit
    const bool isSigned = isCT;                       // CT stores signed HU
    const char *modality = isCT ? "CT" : isMR ? "MR" : "OT";
    std::string pat = pattern ? std::string(pattern.UTF8String) : "sphere";

    char studyUID[100], seriesUID[100], forUID[100];
    dcmGenerateUniqueIdentifier(studyUID, SITE_STUDY_UID_ROOT);
    dcmGenerateUniqueIdentifier(seriesUID, SITE_SERIES_UID_ROOT);
    dcmGenerateUniqueIdentifier(forUID, SITE_UID_ROOT);

    NSMutableArray *paths = [NSMutableArray array];
    const int nPix = rows * columns;
    for (int z = 0; z < slices; z++) {
        DcmFileFormat ff;
        DcmDataset *ds = ff.getDataset();
        char uid[100];
        ds->putAndInsertString(DCM_SOPClassUID, sop);
        ds->putAndInsertString(DCM_SOPInstanceUID, dcmGenerateUniqueIdentifier(uid, SITE_INSTANCE_UID_ROOT));
        ds->putAndInsertString(DCM_StudyInstanceUID, studyUID);
        ds->putAndInsertString(DCM_SeriesInstanceUID, seriesUID);
        ds->putAndInsertString(DCM_FrameOfReferenceUID, forUID);
        ds->putAndInsertString(DCM_PatientName, "SYNTH^Phantom");
        ds->putAndInsertString(DCM_PatientID, "SYNTH-001");
        ds->putAndInsertString(DCM_Modality, modality);
        ds->putAndInsertString(DCM_StudyDate, "20260101");
        ds->putAndInsertString(DCM_StudyID, "1");
        ds->putAndInsertString(DCM_SeriesNumber, "1");
        ds->putAndInsertString(DCM_SeriesDescription, pat.c_str());
        char inst[16]; snprintf(inst, sizeof(inst), "%d", z + 1);
        ds->putAndInsertString(DCM_InstanceNumber, inst);
        // Geometry so it stacks as a uniform volume (2 mm slices, 1 mm pixels).
        ds->putAndInsertString(DCM_ImageOrientationPatient, "1\\0\\0\\0\\1\\0");
        char ipp[64]; snprintf(ipp, sizeof(ipp), "0\\0\\%d", z * 2);
        ds->putAndInsertString(DCM_ImagePositionPatient, ipp);
        ds->putAndInsertString(DCM_PixelSpacing, "1\\1");
        ds->putAndInsertString(DCM_SliceThickness, "2");
        // Image Pixel module.
        ds->putAndInsertUint16(DCM_Rows, (Uint16)rows);
        ds->putAndInsertUint16(DCM_Columns, (Uint16)columns);
        ds->putAndInsertUint16(DCM_SamplesPerPixel, 1);
        ds->putAndInsertString(DCM_PhotometricInterpretation, "MONOCHROME2");
        float fz = slices > 1 ? (float)z / (slices - 1) : 0.5f;
        if (bits16) {
            ds->putAndInsertUint16(DCM_BitsAllocated, 16);
            ds->putAndInsertUint16(DCM_BitsStored, 16);
            ds->putAndInsertUint16(DCM_HighBit, 15);
            ds->putAndInsertUint16(DCM_PixelRepresentation, isSigned ? 1 : 0);
            ds->putAndInsertString(DCM_WindowCenter, isCT ? "0" : "1000");
            ds->putAndInsertString(DCM_WindowWidth, "2000");
            if (isCT) { ds->putAndInsertString(DCM_RescaleIntercept, "0"); ds->putAndInsertString(DCM_RescaleSlope, "1"); }
            std::vector<Uint16> buf(nPix);
            for (int y = 0; y < rows; y++)
                for (int x = 0; x < columns; x++) {
                    float v = patternValue(pat, (float)x / columns, (float)y / rows, fz, x, y, z);
                    if (isSigned) {
                        Sint16 hu = (Sint16)(-1000.0f + v * 2000.0f);   // air … dense
                        buf[y * columns + x] = (Uint16)hu;
                    } else {
                        buf[y * columns + x] = (Uint16)(v * 4000.0f);   // 0 … 4000
                    }
                }
            ds->putAndInsertUint16Array(DCM_PixelData, buf.data(), (unsigned long)nPix);
        } else {
            ds->putAndInsertUint16(DCM_BitsAllocated, 8);
            ds->putAndInsertUint16(DCM_BitsStored, 8);
            ds->putAndInsertUint16(DCM_HighBit, 7);
            ds->putAndInsertUint16(DCM_PixelRepresentation, 0);
            std::vector<Uint8> buf(nPix);
            for (int y = 0; y < rows; y++)
                for (int x = 0; x < columns; x++) {
                    float v = patternValue(pat, (float)x / columns, (float)y / rows, fz, x, y, z);
                    buf[y * columns + x] = (Uint8)(v * 255.0f);
                }
            ds->putAndInsertUint8Array(DCM_PixelData, buf.data(), (unsigned long)nPix);
        }
        NSString *p = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"synth-%04d.dcm", z]];
        if (ff.saveFile(p.fileSystemRepresentation, EXS_LittleEndianExplicit).good())
            [paths addObject:p];
    }
    return @{@"success": @(paths.count > 0), @"count": @(paths.count),
             @"dir": dir, @"files": paths,
             @"message": [NSString stringWithFormat:@"Generated %lu %s slice(s)", (unsigned long)paths.count, modality]};
}

@end
