#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 元抖 Hook 状态登记中心（Hook Safe Guard 的记录层）
 *
 * 所有 Hook / 依赖类在初始化时经过统一登记：
 *  - 类 / Selector 是否存在
 *  - Hook 组是否成功初始化
 *  - 当前环境是否支持
 *
 * 状态中心与诊断报告从这里读取，用于判断"部分功能不可用"的具体原因。
 */
typedef NS_ENUM(NSInteger, DYYYHookStatus) {
    DYYYHookStatusSupported = 0,   // 类/方法存在，Hook 生效
    DYYYHookStatusUnsupported = 1, // 类或方法不存在（抖音更新导致），自动跳过
    DYYYHookStatusDisabled = 2,    // 用户关闭或安全模式下主动跳过
    DYYYHookStatusFailed = 3,      // 尝试 Hook 但发生异常
};

@interface DYYYHookRecord : NSObject
@property(nonatomic, copy) NSString *hookID;      // 逻辑名，如 "播放增强.倍速"
@property(nonatomic, copy) NSString *className;  // 目标类名（可为 Swift 命名空间类）
@property(nonatomic, copy) NSString *selectorName;
@property(nonatomic, assign) DYYYHookStatus status;
@property(nonatomic, copy) NSString *detail;
@property(nonatomic, strong) NSDate *recordedAt;
@end

@interface DYYYHookManager : NSObject

+ (instancetype)shared;

/**
 * 检查类与 Selector 是否存在（Hook 前的安全检查）
 * @return YES 表示可以安全 Hook；同时自动登记一条记录
 */
+ (BOOL)checkClass:(nullable NSString *)className
          selector:(nullable NSString *)selectorName
            hookID:(NSString *)hookID;

/// 只检查类是否存在并登记
+ (BOOL)checkClass:(nullable NSString *)className hookID:(NSString *)hookID;

/**
 * 登记一条 Hook 状态（供 %ctor 中各组初始化后汇报）
 * @param detail 失败/降级原因描述
 */
+ (void)recordHookWithID:(NSString *)hookID
                  className:(nullable NSString *)className
               selectorName:(nullable NSString *)selectorName
                     status:(DYYYHookStatus)status
                     detail:(nullable NSString *)detail;

/// 全部登记记录
+ (NSArray<DYYYHookRecord *> *)allRecords;

/// 失败/不兼容记录数
+ (NSUInteger)problemCount;

/// 一行摘要，如 "24 生效 / 2 不兼容"
+ (NSString *)summaryText;

/// 生成 Hook 状态明细文本（诊断报告用）
+ (NSString *)reportString;

/// 清空登记（用于测试）
+ (void)reset;

@end

NS_ASSUME_NONNULL_END
