// DYYYModeManager.h — DYAll 5.0 模式系统
// Standard / Clean / Immersive / Performance / Battery / Custom
// 切换模式自动处理功能依赖、冲突与性能档案，全部映射到真实偏好键。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYModeManager : NSObject

+ (instancetype)shared;

/// 全部模式：@[ @{ id, name, subtitle } ]
- (NSArray<NSDictionary<NSString *, NSString *> *> *)allModes;
/// 当前模式 ID（持久化）。
- (NSString *)currentModeID;
/// 应用模式：批量写入键、刷新依赖方、记录到当前模式。返回应用的键数量。
- (NSUInteger)applyMode:(NSString *)modeID;
/// 模式的中文说明（详情行用）。
- (NSString *)subtitleForMode:(NSString *)modeID;

@end

/// 模式切换完成后发出的通知（玻璃引擎等据此全量刷新）。
FOUNDATION_EXPORT NSString * const DYYYModeDidChangeNotification;

NS_ASSUME_NONNULL_END
