// DYYYConfigManager.m — 统一配置管理实现
#import "DYYYConfigManager.h"

NSString * const DYYYConfigSchemaVersionCurrent = @"5.0";
NSString * const DYYYConfigLegacySchemaVersion  = @"4.2";
static NSString * const kDYYYConfigFolder       = @"DYYY";
static NSString * const kDYYYConfigAutoBackup   = @"config_autobackup.json";
static NSString * const kDYYYConfigMetaKey      = @"DYYY.ConfigMetadata"; // 内部元数据自存键

@implementation DYYYConfigManager

+ (instancetype)shared {
    static DYYYConfigManager *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[DYYYConfigManager alloc] init]; });
    return inst;
}

#pragma mark 目录

+ (NSString *)configFolderPath {
    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [doc stringByAppendingPathComponent:kDYYYConfigFolder];
}

+ (BOOL)ensureConfigFolder {
    return [[NSFileManager defaultManager] createDirectoryAtPath:[self configFolderPath]
                                      withIntermediateDirectories:YES attributes:nil error:nil];
}

#pragma mark 键管理

+ (BOOL)isManagedKey:(NSString *)key {
    if (key.length == 0 || key.length > 128) return NO;
    static NSArray<NSString *> *prefixes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ prefixes = @[ @"DYYY", @"YTT." ]; });
    for (NSString *p in prefixes) {
        if ([key hasPrefix:p]) return YES;
    }
    return NO;
}

+ (BOOL)isValidValue:(id)value {
    return [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]]
        || [value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]]
        || [value isKindOfClass:[NSDate class]];
}

- (NSArray<NSString *> *)managedKeys {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary *all = defs.dictionaryRepresentation;
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *k in all.allKeys) {
        if ([DYYYConfigManager isManagedKey:k]) [keys addObject:k];
    }
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark 元数据

- (NSDictionary<NSString *, id> *)configMetadata {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary<NSString *, id> *meta = [[defs dictionaryForKey:kDYYYConfigMetaKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    meta[@"schemaVersion"] = DYYYConfigSchemaVersionCurrent;
    meta[@"configVersion"] = @(1);
    meta[@"appVersion"]    = @"5.0";
    if (!meta[@"timestamp"]) meta[@"timestamp"] = @"";
    return [meta copy];
}

- (void)saveMetadata:(NSDictionary<NSString *, id> *)meta {
    [[NSUserDefaults standardUserDefaults] setObject:meta forKey:kDYYYConfigMetaKey];
}

#pragma mark 导出

- (NSString *)exportFileNameWithPrefix:(NSString *)prefix {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    return [NSString stringWithFormat:@"%@_%@.json", prefix, [fmt stringFromDate:[NSDate date]]];
}

- (NSString *)exportConfigWithError:(NSError **)error {
    if (![DYYYConfigManager ensureConfigFolder]) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:1 userInfo:@{NSLocalizedDescriptionKey : @"无法创建配置目录"}];
        return nil;
    }
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary<NSString *, id> *data = [NSMutableDictionary dictionary];
    for (NSString *k in [self managedKeys]) {
        id v = [defs objectForKey:k];
        if ([DYYYConfigManager isValidValue:v]) data[k] = v;
    }
    NSDictionary *payload = @{
        @"schemaVersion" : DYYYConfigSchemaVersionCurrent,
        @"configVersion" : @(1),
        @"appVersion"    : @"5.0",
        @"timestamp"     : [[NSDate date] description],
        @"keyCount"      : @(data.count),
        @"data"          : [data copy],
    };
    NSString *path = [[DYYYConfigManager configFolderPath] stringByAppendingPathComponent:[self exportFileNameWithPrefix:@"DYAll_config"]];
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:error];
    if (!json) return nil;
    BOOL ok = [json writeToFile:path atomically:YES];
    if (!ok) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:2 userInfo:@{NSLocalizedDescriptionKey : @"写入文件失败"}];
        return nil;
    }
    return path;
}

#pragma mark 校验 + 迁移 + 应用

- (NSUInteger)applyPayload:(NSDictionary *)payload error:(NSError **)error {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:10 userInfo:@{NSLocalizedDescriptionKey : @"配置根节点必须是字典"}];
        return 0;
    }
    NSString *schema = payload[@"schemaVersion"];
    if (![schema isKindOfClass:[NSString class]]) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:11 userInfo:@{NSLocalizedDescriptionKey : @"缺少 schemaVersion"}];
        return 0;
    }
    BOOL known = [schema isEqualToString:DYYYConfigSchemaVersionCurrent] || [schema isEqualToString:DYYYConfigLegacySchemaVersion];
    if (!known) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:12 userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"不支持的配置版本 %@", schema]}];
        return 0;
    }
    id dataObj = payload[@"data"];
    if (![dataObj isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:13 userInfo:@{NSLocalizedDescriptionKey : @"缺少 data 字典"}];
        return 0;
    }
    NSDictionary<NSString *, id> *data = dataObj;
    if (data.count > 500) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:14 userInfo:@{NSLocalizedDescriptionKey : @"配置键数量超出限制"}];
        return 0;
    }

    // 升级版本前先自动备份，防丢配置
    [self exportConfigWithError:nil];

    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSUInteger applied = 0;
    for (NSString *k in data.allKeys) {
        if (![DYYYConfigManager isManagedKey:k]) continue;   // 键白名单：静默跳过
        id v = data[k];
        if (![DYYYConfigManager isValidValue:v]) continue;   // 类型校验
        if ([v isKindOfClass:[NSDate class]]) v = [v description];
        // 4.2 → 5.0 迁移：本版本键名与 4.2 兼容，值直接映射；
        // 未来如改键名，在此处按 schemaVersion 分支重映射。
        [defs setObject:v forKey:k];
        applied++;
    }
    [defs synchronize];
    NSMutableDictionary *meta = [[self configMetadata] mutableCopy];
    meta[@"timestamp"] = [[NSDate date] description];
    meta[@"migratedFrom"] = schema;
    [self saveMetadata:meta];
    return applied;
}

- (NSUInteger)importConfigFromFile:(NSString *)path error:(NSError **)error {
    NSData *raw = [NSData dataWithContentsOfFile:path];
    if (!raw) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:20 userInfo:@{NSLocalizedDescriptionKey : @"无法读取文件"}];
        return 0;
    }
    NSError *jsonError = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:raw options:0 error:&jsonError];
    if (jsonError) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:21 userInfo:@{NSLocalizedDescriptionKey : @"JSON 解析失败"}];
        return 0;
    }
    return [self applyPayload:obj error:error];
}

#pragma mark 备份 / 恢复

- (nullable NSString *)latestBackupPath {
    if (![DYYYConfigManager ensureConfigFolder]) return nil;
    NSString *path = [[DYYYConfigManager configFolderPath] stringByAppendingPathComponent:kDYYYConfigAutoBackup];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary *all = defs.dictionaryRepresentation;
    if (all.count == 0) return nil;
    NSMutableDictionary<NSString *, id> *data = [NSMutableDictionary dictionary];
    for (NSString *k in all.allKeys) {
        if ([DYYYConfigManager isManagedKey:k]) {
            id v = all[k];
            if ([DYYYConfigManager isValidValue:v]) data[k] = v;
        }
    }
    NSDictionary *payload = @{
        @"schemaVersion" : DYYYConfigSchemaVersionCurrent,
        @"configVersion" : @(1),
        @"appVersion"    : @"5.0",
        @"timestamp"     : [[NSDate date] description],
        @"data"          : [data copy],
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    if (!json) return nil;
    [json writeToFile:path atomically:YES];
    return path;
}

- (NSUInteger)restoreLatestBackup:(NSError **)error {
    NSString *path = [[DYYYConfigManager configFolderPath] stringByAppendingPathComponent:kDYYYConfigAutoBackup];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error) *error = [NSError errorWithDomain:@"DYYYConfig" code:30 userInfo:@{NSLocalizedDescriptionKey : @"尚无自动备份"}];
        return 0;
    }
    return [self importConfigFromFile:path error:error];
}

@end
