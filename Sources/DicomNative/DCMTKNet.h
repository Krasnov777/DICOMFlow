#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C facade over DCMTK's dcmnet (DIMSE networking).
/// All SCU calls are synchronous; run them off the main thread.
@interface DCMTKNet : NSObject

/// Enable DCMTK DEBUG logging to stderr (diagnostics).
+ (void)enableVerboseLogging;

/// Timeout (seconds) for TCP connect, association negotiation, and each DIMSE
/// message on every outgoing SCU. <= 0 disables (DCMTK default: block forever).
/// Default: 15.
+ (void)setNetworkTimeout:(int)seconds;

/// TLS for every outgoing SCU connection (BCP 195 profile, TLS 1.2+).
/// verifyPeer=NO accepts any server certificate; when verifying, `caFile` is an
/// optional PEM of trusted CA/self-signed certificate(s).
+ (void)setTLSEnabled:(BOOL)enabled verifyPeer:(BOOL)verifyPeer caFile:(nullable NSString *)caFile;

/// C-ECHO. Returns @{ success:NSNumber, echoStatus:NSNumber, message:NSString,
/// sopClasses:NSArray<NSString> }.
+ (NSDictionary *)echoToHost:(NSString *)host port:(int)port
                    calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE;

/// C-STORE a set of files. Returns @{ success, sent, total, message }.
+ (NSDictionary *)storeFiles:(NSArray<NSString *> *)paths
                      toHost:(NSString *)host port:(int)port
                    calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE;

/// C-FIND (study root). Returns @{ success, count, results:NSArray<NSDictionary>, message }.
+ (NSDictionary *)queryHost:(NSString *)host port:(int)port
                   calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE
                      level:(NSString *)level
                    filters:(NSDictionary<NSString *, NSString *> *)filters;

/// C-FIND on the Modality Worklist Information Model. `filters` may include
/// PatientName/PatientID/AccessionNumber (top level) and Modality/
/// ScheduledStationAETitle/ScheduledProcedureStepStartDate (scheduled step).
/// Returns @{ success, count, results:[flattened dicts], message }.
+ (NSDictionary *)worklistQueryHost:(NSString *)host port:(int)port
                           calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE
                            filters:(NSDictionary<NSString *, NSString *> *)filters;

/// C-MOVE (to a destination AE) or C-GET (to a local dir). method = "move"|"get".
/// Returns @{ success, received, receivedDir, message }.
+ (NSDictionary *)retrieveFromHost:(NSString *)host port:(int)port
                          calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE
                             level:(NSString *)level
                              keys:(NSDictionary<NSString *, NSString *> *)keys
                            method:(NSString *)method
                          moveDest:(nullable NSString *)moveDest
                         outputDir:(NSString *)outputDir;

// Built-in Storage SCP (runs on a background thread). When enforceCalledAE is
// YES, associations whose Called AE Title != `ae` are refused.
+ (NSDictionary *)startSCPWithAETitle:(NSString *)ae port:(int)port outputDir:(NSString *)dir
                      enforceCalledAE:(BOOL)enforceCalledAE;
+ (NSDictionary *)stopSCP;
+ (NSDictionary *)scpStatus;
+ (NSArray<NSDictionary *> *)scpReceivedFrom:(NSString *)dir;

/// Negotiation probe: propose a matrix of storage SOP classes × transfer
/// syntaxes and report which presentation contexts the peer accepts (and with
/// which transfer syntaxes). Honors the global TLS/timeout settings.
/// Returns @{ success, message,
///            results:[ @{ sopClass, sopName, accepted, transferSyntaxes:[names] } ] }.
+ (NSDictionary *)probeContextsHost:(NSString *)host port:(int)port
                           calledAE:(NSString *)calledAE callingAE:(NSString *)callingAE;

// Writes a minimal valid Secondary-Capture DICOM file (used by tests / loopback
// checks). Returns YES on success.
+ (BOOL)writeTestImageToPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
