#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 元抖崩溃防护 + 安全模式
 *
 * 目标：一个功能崩了，不能拖死整个抖音。
 *
 * 工作方式：
 *  1. 安装 NSException 处理器 + 信号处理器（SIGABRT/SIGSEGV/SIGBUS/SIGILL/SIGFPE）
 *  2. 崩溃瞬间写入崩溃标记（信号处理器内只做 async-signal-safe 的 open/write/close）
 *  3. 下次启动读取标记 → 连续崩溃计数 +1
 *  4. 连续 3 次崩溃 → 自动进入安全模式：
 *     - 跳过实验性/高风险 Hook 组（AutoPlay、贴纸菜单、激励挂件等）
 *     - 关闭液态玻璃等重 UI 效果
 *     - 状态中心明确提示，用户可在设置中手动退出安全模式
 *  5. 稳定运行 5 分钟后自动清零计数
 */
@interface DYYYSafetyGuard : NSObject

/// 在 %ctor 最前面调用
+ (void)install;

/// 当前是否处于安全模式
+ (BOOL)isSafeMode;

/// 当前连续崩溃计数
+ (NSUInteger)consecutiveCrashCount;

/// 手动退出安全模式（状态中心入口）
+ (void)exitSafeMode;

/// 最近一次崩溃的描述（无则返回 nil）
+ (nullable NSString *)lastCrashDescription;

@end

NS_ASSUME_NONNULL_END
