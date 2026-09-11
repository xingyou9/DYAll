// DYYYFeatureRegistry.h — DYAll 5.0 统一功能注册表
// 所有功能以描述符注册：ID / Name / Category / Enabled / Dependencies / Conflicts / MinVersion / RiskLevel / Status。
// 开关读写统一走 Registry，冲突与依赖自动检测，不再各功能各自维护状态。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DYYYFeatureRisk) {
    DYYYFeatureRiskLow    = 0,
    DYYYFeatureRiskMedium = 1,
    DYYYFeatureRiskHigh   = 2,
};

@interface DYYYFeatureDescriptor : NSObject
@property (nonatomic, copy, readonly) NSString *featureID;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *category;
@property (nonatomic, copy, readonly) NSString *prefKey;
@property (nonatomic, copy, readonly) NSArray<NSString *> *dependencies;   // featureID 列表
@property (nonatomic, copy, readonly) NSArray<NSString *> *conflicts;      // featureID 列表
@property (nonatomic, copy, readonly) NSString *minAppVersion;
@property (nonatomic, copy, readonly) NSString *maxAppVersion;             // 空串 = 无上限
@property (nonatomic, assign, readonly) DYYYFeatureRisk riskLevel;
@end

@interface DYYYFeatureRegistry : NSObject

+ (instancetype)shared;

- (NSArray<DYYYFeatureDescriptor *> *)allFeatures;
- (nullable DYYYFeatureDescriptor *)featureForPrefKey:(NSString *)key;
- (nullable DYYYFeatureDescriptor *)featureForID:(NSString *)featureID;
- (BOOL)isEnabledForFeature:(DYYYFeatureDescriptor *)feature;

/// 开启 feature 前调用：返回因冲突而不能同时开启的功能显示名列表（空 = 无冲突）。
- (NSArray<NSString *> *)conflictNamesIfEnabling:(DYYYFeatureDescriptor *)feature;
/// 开启 feature 前调用：返回尚未满足的依赖显示名列表（空 = 依赖满足）。
- (NSArray<NSString *> *)unmetDependencyNamesIfEnabling:(DYYYFeatureDescriptor *)feature;

/// 统一写入口：写偏好、记录最近使用、广播变更通知。
- (void)setEnabled:(BOOL)enabled forFeature:(DYYYFeatureDescriptor *)feature;

/// 最近使用记录（显示名，按最近排序）。
- (void)recordUseOfPrefKey:(NSString *)key;
- (NSArray<NSString *> *)recentlyUsedNames:(NSUInteger)maxCount;

/// 风险等级描述（诊断页用）。
+ (NSString *)riskTextForLevel:(DYYYFeatureRisk)level;

@end

/// 5.0 变更广播：开关经 Registry 写入后发出，玻璃引擎/透明度等监听方据此刷新。
FOUNDATION_EXPORT NSString * const DYYYFeatureDidChangeNotification;

NS_ASSUME_NONNULL_END
