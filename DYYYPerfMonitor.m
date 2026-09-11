// DYYYPerfMonitor.m — 性能中心实现（真实系统指标，无伪造数据）
#import "DYYYPerfMonitor.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <os/proc.h>

NSString * const DYYYPerfOptimizeNotification = @"DYYYPerfOptimizeNotification";
static NSString * const kDYYYAutoOptimizeKey  = @"DYYY.AutoOptimize";

static BOOL gLowMemActive = NO;
static NSDate *gLowMemUntil = nil;

BOOL DYYYPerfLowMemoryActive(void) {
    if (gLowMemActive && gLowMemUntil && [gLowMemUntil timeIntervalSinceNow] < 0) {
        gLowMemActive = NO;
    }
    return gLowMemActive;
}

@implementation DYYYPerfMonitor {
    CADisplayLink *_fpsLink;
    NSUInteger _fpsFrames;
    NSDate *_fpsWindowStart;
    double _latestFPS;
}

+ (instancetype)shared {
    static DYYYPerfMonitor *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[DYYYPerfMonitor alloc] init];
        [inst registerAutoOptimize];
    });
    return inst;
}

+ (BOOL)lowMemoryWarningActive {
    return DYYYPerfLowMemoryActive();
}

- (void)registerAutoOptimize {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:kDYYYAutoOptimizeKey] == nil) {
        [defs setBool:YES forKey:kDYYYAutoOptimizeKey];   // 默认开启自动优化
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onMemoryWarning)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
}

- (void)onMemoryWarning {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs boolForKey:kDYYYAutoOptimizeKey]) {
        [self performOptimizationNow];
    }
}

- (void)performOptimizationNow {
    gLowMemActive = YES;
    gLowMemUntil = [NSDate dateWithTimeIntervalSinceNow:60.0];   // 60s 后自动恢复特效
    [[NSNotificationCenter defaultCenter] postNotificationName:DYYYPerfOptimizeNotification object:nil];
}

#pragma mark 指标

- (double)memoryUsedMB {
    struct task_vm_info info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return (double)info.phys_footprint / (1024.0 * 1024.0);
}

- (double)memoryAvailableMB {
    // os_proc_available_memory iOS 13+
    if (&os_proc_available_memory != NULL) {
        return (double)os_proc_available_memory() / (1024.0 * 1024.0);
    }
    return -1;
}

- (double)cpuUsagePercent {
    // 公开 API：MACH_TASK_BASIC_INFO 累计 CPU 时间，双窗采样求占比
    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    uint64_t t1 = (uint64_t)info.user_time.seconds * 1000000000ULL + (uint64_t)info.user_time.microseconds * 1000ULL
                + (uint64_t)info.system_time.seconds * 1000000000ULL + (uint64_t)info.system_time.microseconds * 1000ULL;
    usleep(200 * 1000);
    count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    uint64_t t2 = (uint64_t)info.user_time.seconds * 1000000000ULL + (uint64_t)info.user_time.microseconds * 1000ULL
                + (uint64_t)info.system_time.seconds * 1000000000ULL + (uint64_t)info.system_time.microseconds * 1000ULL;
    double deltaNs = (double)(t2 - t1);
    double percent = deltaNs / (200.0 * 1000.0 * 1000.0) * 100.0;
    return MIN(percent, 100.0);
}

- (double)batteryLevel {
    UIDevice *dev = [UIDevice currentDevice];
    dev.batteryMonitoringEnabled = YES;
    double lv = dev.batteryLevel;   // -1 = 模拟器/未知
    if (lv < 0) return -1;
    return lv;
}

#pragma mark FPS

- (void)startFPSsampling {
    if (_fpsLink) return;
    __weak typeof(self) weakSelf = self;
    _fpsLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(fpsTick:)];
    _fpsLink.preferredFramesPerSecond = 0;
    [_fpsLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    _fpsFrames = 0;
    _fpsWindowStart = [NSDate date];
    _latestFPS = 0;
}

- (void)fpsTick:(CADisplayLink *)link {
    _fpsFrames++;
    NSTimeInterval elapsed = -[_fpsWindowStart timeIntervalSinceNow];
    if (elapsed >= 1.0) {
        _latestFPS = _fpsFrames / elapsed;
        _fpsFrames = 0;
        _fpsWindowStart = [NSDate date];
    }
}

- (void)stopFPSsampling {
    [_fpsLink invalidate];
    _fpsLink = nil;
    _latestFPS = 0;
}

- (double)latestFPS {
    return _latestFPS;
}

- (void)dealloc {
    [self stopFPSsampling];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
