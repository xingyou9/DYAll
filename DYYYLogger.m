#import "DYYYLogger.h"
#import "DYYYConstants.h"

static const NSUInteger kDYYYLogMemoryCapacity = 800;
static const NSUInteger kDYYYLogMaxDaysOnDisk = 7;

@implementation DYYYLogEntry

- (NSString *)levelName {
    switch (_level) {
        case DYYYLogLevelDebug:   return @"DEBUG";
        case DYYYLogLevelInfo:    return @"INFO";
        case DYYYLogLevelWarning: return @"WARN";
        case DYYYLogLevelError:   return @"ERROR";
        case DYYYLogLevelFatal:   return @"FATAL";
    }
    return @"INFO";
}

- (NSString *)formattedLine {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      formatter = [[NSDateFormatter alloc] init];
      formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });
    NSString *moduleName = _module.length > 0 ? _module : @"Core";
    return [NSString stringWithFormat:@"%@ [%@][%@] %@", [formatter stringFromDate:_timestamp], self.levelName, moduleName, _message];
}

@end

@interface DYYYLogger ()
@property(nonatomic, strong) NSMutableArray<DYYYLogEntry *> *buffer;
@property(nonatomic, strong) dispatch_queue_t logQueue;
@end

@implementation DYYYLogger

+ (instancetype)shared {
    static DYYYLogger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffer = [NSMutableArray arrayWithCapacity:kDYYYLogMemoryCapacity];
        _logQueue = dispatch_queue_create("com.dyyy.logger.queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (void)startup {
    [[self shared] logWithLevel:DYYYLogLevelInfo module:@"Core" message:[NSString stringWithFormat:@"元抖启动 v%@", DYYY_VERSION]];
}

+ (BOOL)verboseEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableVerboseLog"];
}

- (void)logWithLevel:(DYYYLogLevel)level module:(NSString *)module message:(NSString *)message {
    if (level == DYYYLogLevelDebug && ![DYYYLogger verboseEnabled]) {
        return;
    }
    if (!message) {
        message = @"(empty)";
    }
    if (message.length > 2000) {
        message = [[message substringToIndex:2000] stringByAppendingString:@"…(截断)"];
    }

    dispatch_async(self.logQueue, ^{
      DYYYLogEntry *entry = [[DYYYLogEntry alloc] init];
      entry.level = level;
      entry.timestamp = [NSDate date];
      entry.module = [module copy] ?: @"";
      entry.message = [message copy];

      [self.buffer insertObject:entry atIndex:0];
      if (self.buffer.count > kDYYYLogMemoryCapacity) {
          [self.buffer removeObjectsInRange:NSMakeRange(kDYYYLogMemoryCapacity, self.buffer.count - kDYYYLogMemoryCapacity)];
      }

      [self appendToDisk:entry];
    });
}

- (void)appendToDisk:(DYYYLogEntry *)entry {
    @try {
        NSString *dir = [DYYYLogger logsDirectory];
        if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }

        static NSDateFormatter *fileFormatter;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          fileFormatter = [[NSDateFormatter alloc] init];
          fileFormatter.dateFormat = @"yyyy-MM-dd";
        });

        // 落盘级别控制：Debug 不写盘，避免无意义 IO
        if (entry.level <= DYYYLogLevelDebug) {
            return;
        }

        NSString *filePath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"dyyy-%@.log", [fileFormatter stringFromDate:entry.timestamp]]];
        NSString *line = [entry.formattedLine stringByAppendingString:@"\n"];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
        if (handle) {
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        } else {
            [line writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }

        [self cleanOldLogFilesInDirectory:dir];
    } @catch (NSException *exception) {
        // 日志自身失败绝不能影响主流程
    }
}

- (void)cleanOldLogFilesInDirectory:(NSString *)dir {
    static NSDateFormatter *fileFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      fileFormatter = [[NSDateFormatter alloc] init];
      fileFormatter.dateFormat = @"yyyy-MM-dd";
    });

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    if (files.count <= kDYYYLogMaxDaysOnDisk) {
        return;
    }

    NSDate *threshold = [NSDate dateWithTimeIntervalSinceNow:-((NSTimeInterval)kDYYYLogMaxDaysOnDisk * 24 * 3600)];
    for (NSString *name in files) {
        if (![name hasPrefix:@"dyyy-"] || ![name hasSuffix:@".log"]) {
            continue;
        }
        NSString *datePart = [name substringWithRange:NSMakeRange(5, 10)];
        NSDate *date = [fileFormatter dateFromString:datePart];
        if (date && [date compare:threshold] == NSOrderedAscending) {
            [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
        }
    }
}

#pragma mark - 类方法便捷入口

+ (void)debug:(NSString *)module message:(NSString *)message {
    [[self shared] logWithLevel:DYYYLogLevelDebug module:module message:message];
}

+ (void)info:(NSString *)module message:(NSString *)message {
    [[self shared] logWithLevel:DYYYLogLevelInfo module:module message:message];
}

+ (void)warning:(NSString *)module message:(NSString *)message {
    [[self shared] logWithLevel:DYYYLogLevelWarning module:module message:message];
}

+ (void)error:(NSString *)module message:(NSString *)message {
    [[self shared] logWithLevel:DYYYLogLevelError module:module message:message];
}

+ (void)fatal:(NSString *)module message:(NSString *)message {
    [[self shared] logWithLevel:DYYYLogLevelFatal module:module message:message];
}

+ (void)logException:(NSException *)exception module:(NSString *)module {
    if (!exception) {
        return;
    }
    NSString *message = [NSString stringWithFormat:@"%@ (%@)\n%@", exception.name, exception.reason, exception.callStackSymbols];
    [[self shared] logWithLevel:DYYYLogLevelFatal module:module message:message];
}

#pragma mark - 读取

+ (NSArray<DYYYLogEntry *> *)recentLogs {
    __block NSArray<DYYYLogEntry *> *result;
    dispatch_sync([self shared].logQueue, ^{
      result = [[self shared].buffer copy];
    });
    return result ?: @[];
}

+ (NSArray<DYYYLogEntry *> *)recentWarningsAndErrors {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"level >= %d", (NSInteger)DYYYLogLevelWarning];
    return [[self recentLogs] filteredArrayUsingPredicate:predicate];
}

+ (void)clearLogs {
    dispatch_barrier_async([self shared].logQueue, ^{
      [[self shared].buffer removeAllObjects];
    });
    NSString *dir = [self logsDirectory];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *name in files) {
        [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
    }
}

+ (NSString *)logsDirectory {
    NSString *library = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    return [library stringByAppendingPathComponent:@"元抖/Logs"];
}

+ (NSString *)exportText {
    NSMutableString *text = [NSMutableString string];
    NSArray<DYYYLogEntry *> *entries = [self recentLogs];
    // recentLogs 新日志在前，导出时按时间正序
    for (NSUInteger i = entries.count; i > 0; i--) {
        [text appendFormat:@"%@\n", entries[i - 1].formattedLine];
    }
    if (text.length == 0) {
        [text appendString:@"(暂无日志)"];
    }
    return text;
}

@end
