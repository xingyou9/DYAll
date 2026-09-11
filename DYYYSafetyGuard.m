#import "DYYYSafetyGuard.h"
#import "DYYYLogger.h"
#import <UIKit/UIKit.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>

static NSString * const kDYYYCrashCountKey = @"DYYYConsecutiveCrashCount";
static NSString * const kDYYYSafeModeKey = @"DYYYSafeMode";
static NSString * const kDYYYLastCrashInfoKey = @"DYYYLastCrashInfo";
static const NSUInteger kDYYYSafeModeThreshold = 3;
static const NSTimeInterval kDYYYStableResetSeconds = 300;

// 信号处理器可用的崩溃标记路径（提前算好，handler 内不做任何 ObjC 调用）
static char kDYYYCrashMarkerPath[1024];
static volatile sig_atomic_t kDYYYGuardInstalled = 0;

static void DYYYWriteCrashMarker(void) {
    if (kDYYYCrashMarkerPath[0] == '\0') {
        return;
    }
    int fd = open(kDYYYCrashMarkerPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        const char *payload = "crash";
        ssize_t written = write(fd, payload, strlen(payload));
        (void)written;
        fsync(fd);
        close(fd);
    }
}

static void DYYYSignalCrashHandler(int sig) {
    DYYYWriteCrashMarker();
    // 恢复默认处理并重新抛出，保持系统正常崩溃报告
    signal(sig, SIG_DFL);
    raise(sig);
}

static void DYYYUncaughtExceptionHandler(NSException *exception) {
    // NSException 场景仍可安全使用 ObjC 运行时
    @try {
        NSString *info = [NSString stringWithFormat:@"%@: %@\n%@", exception.name, exception.reason, [exception.callStackSymbols componentsJoinedByString:@"\n"]];
        [[NSUserDefaults standardUserDefaults] setObject:info forKey:kDYYYLastCrashInfoKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } @catch (NSException *swallow) {
        (void)swallow;
    }
    DYYYWriteCrashMarker();
}

@implementation DYYYSafetyGuard

+ (NSString *)markerPath {
    NSString *library = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    return [library stringByAppendingPathComponent:@"元抖/crash.marker"];
}

+ (void)install {
    if (kDYYYGuardInstalled) {
        return;
    }
    kDYYYGuardInstalled = 1;

    // 1. 预计算崩溃标记路径
    NSString *markerPath = [self markerPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:markerPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    strlcpy(kDYYYCrashMarkerPath, markerPath.fileSystemRepresentation, sizeof(kDYYYCrashMarkerPath));

    // 2. 安装处理器
    NSSetUncaughtExceptionHandler(DYYYUncaughtExceptionHandler);
    signal(SIGABRT, DYYYSignalCrashHandler);
    signal(SIGSEGV, DYYYSignalCrashHandler);
    signal(SIGBUS,  DYYYSignalCrashHandler);
    signal(SIGILL,  DYYYSignalCrashHandler);
    signal(SIGFPE,  DYYYSignalCrashHandler);

    // 3. 处理上一次启动的崩溃
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:markerPath]) {
        [fileManager removeItemAtPath:markerPath error:nil];

        NSUInteger count = [defaults integerForKey:kDYYYCrashCountKey] + 1;
        [defaults setInteger:count forKey:kDYYYCrashCountKey];
        [defaults synchronize];

        [DYYYLogger warning:@"SafetyGuard" message:[NSString stringWithFormat:@"检测到上次运行异常退出，连续崩溃计数 = %lu", (unsigned long)count]];

        if (count >= kDYYYSafeModeThreshold && ![defaults boolForKey:kDYYYSafeModeKey]) {
            [self enterSafeModeWithCrashCount:count];
        }
    } else {
        // 上一次运行是正常退出
        NSUInteger count = [defaults integerForKey:kDYYYCrashCountKey];
        if (count > 0) {
            // 用户手动杀掉 App 也算正常退出，但不立刻清零，只递减，避免误判
            [defaults setInteger:(count > 0 ? count - 1 : 0) forKey:kDYYYCrashCountKey];
            [defaults synchronize];
        }
    }

    // 4. 稳定运行后清零计数
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYYYStableResetSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if ([[NSUserDefaults standardUserDefaults] integerForKey:kDYYYCrashCountKey] != 0) {
          [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:kDYYYCrashCountKey];
          [[NSUserDefaults standardUserDefaults] synchronize];
          [DYYYLogger info:@"SafetyGuard" message:@"运行稳定，连续崩溃计数已清零"];
      }
    });

    [DYYYLogger info:@"SafetyGuard" message:@"崩溃防护已安装（NSException + 信号级）"];
}

+ (void)enterSafeModeWithCrashCount:(NSUInteger)count {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // 记录进入安全模式时正在开启的实验性功能（仅作记录，不覆盖用户偏好）
    NSArray<NSString *> *experimentalKeys = @[
        @"DYYYEnableAutoPlay",
        @"DYYYEnableLongPressSpeedGesture",
        @"DYYYEnableBackgroundListen",
        @"DYYYEnableFloatSpeedButton",
        @"DYYYEnableFloatClearButton",
    ];
    NSMutableArray *enabledList = [NSMutableArray array];
    for (NSString *key in experimentalKeys) {
        if ([defaults boolForKey:key]) {
            [enabledList addObject:key];
        }
    }
    [defaults setObject:enabledList forKey:@"DYYYSafeModeSuspendedFeatures"];
    [defaults setBool:YES forKey:kDYYYSafeModeKey];
    [defaults synchronize];

    [DYYYLogger fatal:@"SafetyGuard" message:[NSString stringWithFormat:@"连续崩溃 %lu 次，已自动进入安全模式（挂起实验功能：%@）", (unsigned long)count, [enabledList componentsJoinedByString:@", "] ?: @"无"]];
}

+ (BOOL)isSafeMode {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDYYYSafeModeKey];
}

+ (NSUInteger)consecutiveCrashCount {
    return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:kDYYYCrashCountKey];
}

+ (void)exitSafeMode {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:NO forKey:kDYYYSafeModeKey];
    [defaults setInteger:0 forKey:kDYYYCrashCountKey];
    [defaults removeObjectForKey:@"DYYYSafeModeSuspendedFeatures"];
    [defaults synchronize];
    [DYYYLogger info:@"SafetyGuard" message:@"用户已手动退出安全模式，重启抖音后完整恢复"];
}

+ (NSString *)lastCrashDescription {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kDYYYLastCrashInfoKey];
}

@end
