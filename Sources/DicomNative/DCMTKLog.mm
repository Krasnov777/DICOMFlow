#import "DCMTKLog.h"

#include "dcmtk/config/osconfig.h"
#include "dcmtk/oflog/oflog.h"
#include "dcmtk/oflog/appender.h"
#include "dcmtk/oflog/logger.h"
#include "dcmtk/oflog/loglevel.h"
#include "dcmtk/oflog/spi/logevent.h"

#include <os/lock.h>

using namespace dcmtk::log4cplus;

// gHandler is read on DCMTK logging threads and reassigned on the main thread;
// ARC retain/release racing with reassignment can crash. Guard both with a lock.
static void (^gHandler)(NSString *, NSString *, NSString *) = nil;
static os_unfair_lock gHandlerLock = OS_UNFAIR_LOCK_INIT;

/// A log4cplus appender that forwards each event to the Objective-C block.
class CallbackAppender : public Appender {
public:
    CallbackAppender() {}
    virtual ~CallbackAppender() { destructorImpl(); }
    virtual void close() override {}

protected:
    virtual void append(const spi::InternalLoggingEvent &event) override {
        os_unfair_lock_lock(&gHandlerLock);
        void (^h)(NSString *, NSString *, NSString *) = gHandler;   // retained by ARC
        os_unfair_lock_unlock(&gHandlerLock);
        if (h == nil) return;
        LogLevel ll = event.getLogLevel();
        NSString *level = ll >= ERROR_LOG_LEVEL ? @"error"
                        : ll >= WARN_LOG_LEVEL  ? @"warn"
                        : ll >= INFO_LOG_LEVEL  ? @"info"
                                                : @"debug";
        NSString *logger  = [NSString stringWithUTF8String:event.getLoggerName().c_str()] ?: @"";
        NSString *message = [NSString stringWithUTF8String:event.getMessage().c_str()] ?: @"";
        h(level, logger, message);
    }
};

@implementation DCMTKLog

+ (void)startWithHandler:(void (^)(NSString *, NSString *, NSString *))handler {
    os_unfair_lock_lock(&gHandlerLock);
    gHandler = [handler copy];
    os_unfair_lock_unlock(&gHandlerLock);
    static SharedAppenderPtr appender;
    if (!appender) {
        appender = SharedAppenderPtr(new CallbackAppender());
        appender->setName("DicomFlowCapture");
        Logger::getRoot().addAppender(appender);
    }
}

+ (void)stop {
    os_unfair_lock_lock(&gHandlerLock);
    gHandler = nil;
    os_unfair_lock_unlock(&gHandlerLock);
}

+ (void)setVerbose:(BOOL)verbose {
    // Scope DEBUG to dcmnet only (its events still propagate to our root appender);
    // leaving root untouched avoids flooding with dcmdata decode logs.
    Logger::getInstance("dcmtk.dcmnet").setLogLevel(verbose ? DEBUG_LOG_LEVEL : INFO_LOG_LEVEL);
}

@end
