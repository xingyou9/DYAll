#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 元抖诊断报告
 *
 * 一键收集售后所需全部信息：
 *  - 版本（插件 / 抖音 / iOS / 设备 / 越狱模式）
 *  - 已启用功能数 / 安全模式状态
 *  - Hook 状态明细（不兼容项及原因）
 *  - 最近错误日志
 *  - 任务统计
 *
 * 结果可直接复制到剪贴板或通过分享面板发送。
 */
@interface DYYYDiagnostics : NSObject

/// 生成完整诊断报告文本
+ (NSString *)generateReport;

/// 统计当前启用的 DYYY 功能数量（仪表盘使用）
+ (NSUInteger)enabledFeatureCount;

/// 生成报告并复制到剪贴板，返回提示文本
+ (NSString *)copyReportToPasteboard;

/// 弹出系统分享面板（需在主线程调用）
+ (void)presentShareSheetForReport;

@end

NS_ASSUME_NONNULL_END
