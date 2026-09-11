// DYYYCacheManager.h — DYAll 5.0 缓存管理：真实统计 + 分类型清理 + 上限自动清理
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYCacheItem : NSObject
@property (nonatomic, copy, readonly) NSString *name;      // 展示名
@property (nonatomic, assign, readonly) unsigned long long bytes;
@property (nonatomic, copy, readonly) NSString *itemID;    // clearItemType 用
@end

@interface DYYYCacheManager : NSObject

+ (instancetype)shared;

/// 全部缓存分类及真实大小（字节）。
- (NSArray<DYYYCacheItem *> *)allItems;
/// 总大小。
- (unsigned long long)totalBytes;

/// 清理指定分类（itemID 见 allItems），返回释放的字节数。
- (unsigned long long)clearItem:(NSString *)itemID;

/// 清理全部可清理项，返回释放的字节数。
- (unsigned long long)clearAll;

/// 检查缓存总量是否超过上限（默认 500MB），超限自动清理临时缓存。返回是否触发。
- (BOOL)autoCleanIfOverLimit;

@end

NS_ASSUME_NONNULL_END
