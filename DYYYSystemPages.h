#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 元抖企业级系统页面集合：状态中心 / 运行日志 / 任务中心 / 设置搜索 / 配置快照

#pragma mark - 状态中心

@interface DYYYStatusViewController : UITableViewController
@end

#pragma mark - 运行日志

@interface DYYYLogViewController : UITableViewController
@end

#pragma mark - 任务中心

@interface DYYYTaskCenterViewController : UITableViewController
@end

#pragma mark - 全局设置搜索

@interface DYYYSettingsSearchViewController : UITableViewController
/// 分类名 → 跳转该分类页面的动作（由设置首页注入）
@property(nonatomic, copy) NSDictionary<NSString *, void (^)(void)> *categoryBlocks;
@end

#pragma mark - 配置快照

@interface DYYYSnapshotViewController : UITableViewController
@end

NS_ASSUME_NONNULL_END
