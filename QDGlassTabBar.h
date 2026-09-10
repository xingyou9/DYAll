//
//  QDGlassTabBar.h
//  YTT 液态玻璃 — 抖音底栏原地换皮
//
//  对外只暴露偏好读取、能力探测与状态文案，实现细节留在 .xm。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 注册默认值（液态玻璃默认开启，其余默认关闭）。
void QDYTTGlassRegisterDefaults(void);

/// 五档开关。
BOOL QDYTTGlassEnabled(void);
BOOL QDYTTGlassClearEnabled(void);
BOOL QDYTTGlassGradientEnabled(void);
BOOL QDYTTGlassCapsuleEnabled(void);
BOOL QDYTTGlassExtendEnabled(void);

/// 悬浮胶囊引擎（iOS 26+ 系统玻璃底栏，加号内联）是否启用。
BOOL QDYTTGlassFloatingEnabled(void);

/// 系统是否真的带原生液态玻璃（iOS 26+ 的 UIGlassEffect）。
BOOL QDYTTGlassNativeAvailable(void);

/// 底栏接管状态，给设置页的状态区显示。
/// 例：@"已接管 · AWENormalModeTabBar · 原生玻璃" / @"未找到底栏"
NSString *QDYTTGlassBarStatus(void);

/// 玻璃当前用的是原生材质还是降级材质。
NSString *QDYTTGlassEngineName(void);

/// 立即重跑一次（开关变化后调用，通常无需手动，心跳会兜底）。
void QDYTTGlassRefresh(void);

NS_ASSUME_NONNULL_END
