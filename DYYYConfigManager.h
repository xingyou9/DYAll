// DYYYConfigManager.h — DYAll 5.0 统一配置管理
// 本地配置 / 默认配置 / Schema 校验 / 版本迁移 / 导入 / 导出 / 备份 / 恢复 / 冲突检测
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const DYYYConfigSchemaVersionCurrent;   // @"5.0"
extern NSString * const DYYYConfigLegacySchemaVersion;    // @"4.2"

@interface DYYYConfigManager : NSObject

+ (instancetype)shared;

/// 当前生效配置的元数据（Schema Version / Config Version / App Version / Timestamp）。
- (NSDictionary<NSString *, id> *)configMetadata;

/// 导出全部 DYAll 配置（DYYY* / YTT* 前缀键），写入 Documents/DYYY/ 下带时间戳的 JSON，
/// 返回文件路径；失败返回 nil。
- (nullable NSString *)exportConfigWithError:(NSError **)error;

/// 从指定 JSON 文件导入配置。先 Schema 校验（版本、键白名单、值类型），再应用；
/// 4.2 旧配置自动迁移到 5.0。返回应用的键数量，失败抛错。
- (NSUInteger)importConfigFromFile:(NSString *)path error:(NSError **)error;

/// 恢复最近一次自动备份；返回恢复的键数量，无备份返回 0。
- (NSUInteger)restoreLatestBackup:(NSError **)error;

/// 自动备份路径（不存在则创建）。升级版本前会先调用。
- (nullable NSString *)latestBackupPath;

/// 配置键白名单（前缀）。
+ (BOOL)isManagedKey:(NSString *)key;

/// 值类型校验：仅允许属性表类型（BOOL/数字/字符串/数组/字典）。
+ (BOOL)isValidValue:(id)value;

@end

NS_ASSUME_NONNULL_END
