// DYYYCacheManager.m — 缓存管理实现（真实目录统计，绝不伪造数字）
#import "DYYYCacheManager.h"

static unsigned long long const kDYYYCacheLimitDefaultMB = 500ULL;
static NSString * const kDYYYCacheLimitKey = @"DYYY.CacheLimitMB";

// 构造期可写
@interface DYYYCacheItem ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, assign, readwrite) unsigned long long bytes;
@property (nonatomic, copy, readwrite) NSString *itemID;
@end

@implementation DYYYCacheItem
@end

@implementation DYYYCacheManager

+ (instancetype)shared {
    static DYYYCacheManager *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[DYYYCacheManager alloc] init]; });
    return inst;
}

+ (NSString *)tempDir  { return NSTemporaryDirectory(); }
+ (NSString *)logsDir  { return [NSTemporaryDirectory() stringByAppendingPathComponent:@"DYYYLogs"]; }
+ (NSString *)configDir {
    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [doc stringByAppendingPathComponent:@"DYYY"];
}

+ (unsigned long long)sizeOfPath:(NSString *)path {
    if (path.length == 0) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) return 0;
    if (!isDir) {
        NSDictionary *attr = [fm attributesOfItemAtPath:path error:nil];
        return attr ? (unsigned long long)[attr fileSize] : 0;
    }
    unsigned long long total = 0;
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:path error:nil];
    for (NSString *child in children) {
        total += [self sizeOfPath:[path stringByAppendingPathComponent:child]];
    }
    return total;
}

+ (unsigned long long)clearPath:(NSString *)path {
    if (path.length == 0) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) return 0;
    unsigned long long before = [self sizeOfPath:path];
    NSError *err = nil;
    [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
    if (err) return 0;
    if (isDir) [fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil];
    return before;
}

- (DYYYCacheItem *)itemWithID:(NSString *)iid name:(NSString *)name bytes:(unsigned long long)bytes {
    DYYYCacheItem *item = [[DYYYCacheItem alloc] init];
    item.itemID = iid;
    item.name = name;
    item.bytes = bytes;
    return item;
}

- (NSArray<DYYYCacheItem *> *)allItems {
    NSMutableArray<DYYYCacheItem *> *items = [NSMutableArray array];
    [items addObject:[self itemWithID:@"temp"   name:@"临时下载文件"   bytes:[DYYYCacheManager sizeOfPath:[DYYYCacheManager tempDir]]]];
    [items addObject:[self itemWithID:@"logs"   name:@"运行日志文件"   bytes:[DYYYCacheManager sizeOfPath:[DYYYCacheManager logsDir]]]];
    [items addObject:[self itemWithID:@"config" name:@"配置与备份文件" bytes:[DYYYCacheManager sizeOfPath:[DYYYCacheManager configDir]]]];
    return [items copy];
}

- (unsigned long long)totalBytes {
    unsigned long long total = 0;
    for (DYYYCacheItem *i in [self allItems]) total += i.bytes;
    return total;
}

- (unsigned long long)clearItem:(NSString *)itemID {
    if ([itemID isEqualToString:@"temp"])   return [DYYYCacheManager clearPath:[DYYYCacheManager tempDir]];
    if ([itemID isEqualToString:@"logs"])   return [DYYYCacheManager clearPath:[DYYYCacheManager logsDir]];
    if ([itemID isEqualToString:@"config"]) return [DYYYCacheManager clearPath:[DYYYCacheManager configDir]];
    return 0;
}

- (unsigned long long)clearAll {
    // 配置目录含用户备份，不参与“全部清理”，只能单独清
    return [self clearItem:@"temp"] + [self clearItem:@"logs"];
}

- (BOOL)autoCleanIfOverLimit {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSUInteger limitMB = [defs integerForKey:kDYYYCacheLimitKey];
    if (limitMB == 0) limitMB = (NSUInteger)kDYYYCacheLimitDefaultMB;
    unsigned long long total = [self totalBytes];
    if (total > limitMB * 1024ULL * 1024ULL) {
        [self clearItem:@"temp"];
        return YES;
    }
    return NO;
}

@end
