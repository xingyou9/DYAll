#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 元抖任务中心
 *
 * 所有异步任务（下载 / 转换 / 导出 / Live Photo）统一登记：
 *
 *   等待 → 运行 → 完成 / 失败 / 取消
 *
 * 下载、媒体处理不再各自维护孤立进度，状态中心页面与
 * 诊断报告统一从这里读取。历史记录持久化在
 * Library/元抖/task_history.plist（上限 100 条）。
 */
typedef NS_ENUM(NSInteger, DYYYTaskState) {
    DYYYTaskStateRunning   = 0,
    DYYYTaskStateDone      = 1,
    DYYYTaskStateFailed    = 2,
    DYYYTaskStateCancelled = 3,
};

extern NSString *DYYYTaskStateName(DYYYTaskState state);

@interface DYYYTaskRecord : NSObject
@property(nonatomic, copy) NSString *taskID;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *type;        // 下载 / 转换 / 导出 / Live Photo
@property(nonatomic, assign) DYYYTaskState state;
@property(nonatomic, assign) float progress;      // 0.0 ~ 1.0
@property(nonatomic, strong) NSDate *createdAt;
@property(nonatomic, strong, nullable) NSDate *finishedAt;
@property(nonatomic, copy, nullable) NSString *fileURL; // 成果或失败源 URL
@property(nonatomic, copy, nullable) NSString *detail;
@property(nonatomic, assign, readonly) BOOL isActive;
@end

@interface DYYYTaskCenter : NSObject

+ (instancetype)shared;

/// 登记一个新任务（同 ID 重复登记会被忽略并告警）
- (void)beginTaskWithID:(NSString *)taskID title:(NSString *)title type:(NSString *)type;

/// 更新运行进度 0.0 ~ 1.0
- (void)updateProgress:(float)progress forTaskID:(NSString *)taskID;

/// 附加描述（如失败原因）
- (void)setDetail:(NSString *)detail forTaskID:(NSString *)taskID;

/// 结束任务（成功 / 失败 / 取消）
- (void)finishTaskWithID:(NSString *)taskID
                 success:(BOOL)success
              cancelled:(BOOL)cancelled
                 fileURL:(nullable NSURL *)fileURL;

/// 运行中任务（新任务在前）
- (NSArray<DYYYTaskRecord *> *)activeTasks;

/// 已结束任务（含成功/失败/取消，新任务在前，最多 100 条）
- (NSArray<DYYYTaskRecord *> *)history;

/// 今日结束的任务数（仪表盘统计）
- (NSUInteger)finishedCountToday;

- (void)clearHistory;

/// 从持久化文件重新加载历史（启动时无需手动调用，首次访问自动加载）
- (void)reloadHistoryIfNeeded;

@end

NS_ASSUME_NONNULL_END
