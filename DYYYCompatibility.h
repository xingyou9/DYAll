#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 元抖兼容性引擎（Dependency Resolver + 自动降级）
 *
 * 启动时统一检测：
 *  - iOS 版本 / 设备型号 / 架构
 *  - 抖音版本是否在已验证范围
 *  - 越狱运行模式（rootful / rootless / roothide）
 *  - 设置页所需关键类是否存在
 *  - 液态玻璃（UIGlassEffect）能力
 *
 * 任何失败只记录 + 降级，绝不让启动崩溃。
 */
@interface DYYYCompatibility : NSObject

/// 在 %ctor 中调用（SafetyGuard 之后）
+ (void)performStartupChecks;

#pragma mark - 环境信息（状态中心 / 诊断报告使用）

+ (NSString *)iOSVersion;
+ (NSString *)deviceModel;
+ (NSString * _Nullable)architectureName;
+ (NSString *)douyinVersion;
+ (NSString *)douyinBuild;
+ (NSString *)jailbreakScheme;

/// 已充分测试的抖音版本（超出该版本只提示"未验证"，不阻断功能）
+ (NSString *)testedDouyinVersion;

/// "已验证" / "未验证（抖音版本较新）" / "未知"
+ (NSString *)douyinCompatibilityStatus;

/// 是否支持 iOS 26 液态玻璃（类存在且 iOS >= 26）
+ (BOOL)glassEffectSupported;

/// 汇总字典（键为中文标签，直接用于状态中心展示）
+ (NSDictionary<NSString *, NSString *> *)environmentInfo;

#pragma mark - 自动降级

/// 安全模式下禁用玻璃；其余情况跟随用户偏好
+ (BOOL)glassUIEnabled;

/// 依赖检查是否全部通过（关键类缺失时返回 NO，设置入口自动隐藏并提示）
+ (BOOL)dependencyCheckPassed;

@end

NS_ASSUME_NONNULL_END
