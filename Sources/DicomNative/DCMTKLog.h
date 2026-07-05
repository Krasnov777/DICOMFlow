#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Captures DCMTK's internal log (log4cplus/oflog) — including the `dcmnet`
/// association + DIMSE PDU dumps — and forwards each event to Swift. This is the
/// data source for the "Protocol" inspector (a decoded view of our own traffic).
@interface DCMTKLog : NSObject

/// Install the capture appender. `handler` is called for every log event with
/// (level: debug|info|warn|error, logger name, message). Called on DCMTK threads.
+ (void)startWithHandler:(void (^)(NSString *level, NSString *logger, NSString *message))handler;

/// Remove the handler (capture appender stays installed but does nothing).
+ (void)stop;

/// Verbose = DCMTK `dcmnet` at DEBUG (full A-ASSOCIATE / DIMSE PDU dumps);
/// otherwise INFO (high-level only).
+ (void)setVerbose:(BOOL)verbose;

@end

NS_ASSUME_NONNULL_END
