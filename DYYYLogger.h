#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 元抖统一日志系统
 *
 * 取代散落各处的 NSLog：
 *  - 分级：Debug / Info / Warning / Error / Fatal
 *  - 线程安全：内部串行队列保护，可在任意线程调用
 *  - 内存环形缓冲（默认 800 条）+ 按天落盘（Library/元抖/Logs/）
 *  - 供状态中心 / 日志查看页 / 诊断报告消费
 */
typedef NS_ENUM(NSInteger, DYYYLogLevel) {
    DYYYLogLevelDebug = 0,
    DYYYLogLevelInfo  = 1,
    DYYYLogLevelWarning = 2,
    DYYYLogLevelError = 3,
    DYYYLogLevelFatal = 4,
};

@interface DYYYLogEntry : NSObject
@property(nonatomic, assign) DYYYLogLevel level;
@property(nonatomic, strong) NSDate *timestamp;
@property(nonatomic, copy) NSString *module;
@property(nonatomic, copy) NSString *message;
/// 形如 "2026-09-11 08:00:00 [WARN][模块] 消息"
@property(nonatomic, copy, readonly) NSString *formattedLine;
@property(nonatomic, copy, readonly) NSString *levelName;
@end

@interface DYYYLogger : NSObject

+ (instancetype)shared;

/// 启动时初始化（写一条启动日志，检查磁盘空间等）。可重复调用。
+ (void)startup;

+ (void)debug:(NSString *)module message:(NSString *)message;
+ (void)info:(NSString *)module message:(NSString *)message;
+ (void)warning:(NSString *)module message:(NSString *)message;
+ (void)error:(NSString *)module message:(NSString *)message;
+ (void)fatal:(NSString *)module message:(NSString *)message;

/// 记录异常对象（异常堆栈取 name/reason/callStackSymbols）
+ (void)logException:(NSException *)exception module:(NSString *)module;

/// 内存缓冲中的最近日志（新日志在前）
+ (NSArray<DYYYLogEntry *> *)recentLogs;

/// 过滤出 warning 及以上级别
+ (NSArray<DYYYLogEntry *> *)recentWarningsAndErrors;

+ (void)clearLogs;

/// 日志目录路径（Library/元抖/Logs）
+ (NSString *)logsDirectory;

/// 导出全部内存日志为一段文本（诊断报告使用）
+ (NSString *)exportText;

/// 是否开启 Debug 级日志（偏好键 DYYYEnableVerboseLog，默认 NO）
+ (BOOL)verboseEnabled;

@end

NS_ASSUME_NONNULL_END
