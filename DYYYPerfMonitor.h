// DYYYPerfMonitor.h — DYAll 5.0 性能中心：真实指标采样 + 自动优化
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYPerfMonitor : NSObject

+ (instancetype)shared;

/// 当前内存占用（MB，物理足迹）。失败返回 -1。
- (double)memoryUsedMB;
/// 可用内存（MB）。失败返回 -1。
- (double)memoryAvailableMB;
/// 当前进程 CPU 占用（%，双采样 200ms）。失败返回 -1。
- (double)cpuUsagePercent;
/// 电量（0~1，未开启电池监测返回 -1）。
- (double)batteryLevel;
/// 是否处于低内存自动优化状态（玻璃引擎等据此降级）。
+ (BOOL)lowMemoryWarningActive;

/// FPS 采样：调用 startFPSsampling 后用 latestFPS 读数；stopFPSsampling 停止（页面退出必须调）。
- (void)startFPSsampling;
- (void)stopFPSsampling;
- (double)latestFPS;

/// 立即执行一次自动优化（清缓存/降特效广播）。
- (void)performOptimizationNow;

@end

/// 自动优化触发后的广播：缓存持有方收到后清掉可重建的缓存。
FOUNDATION_EXPORT NSString * const DYYYPerfOptimizeNotification;

NS_ASSUME_NONNULL_END
