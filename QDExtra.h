//
//  QDExtra.h
//  元抖 — 系统增强模块（灵动岛屏蔽 / 性能与流畅度 / 交互防护）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "AwemeHeaders.h"

NS_ASSUME_NONNULL_BEGIN

@interface QDExtra : NSObject

/// 注册本模块默认值，必须在构造期调用一次。
+ (void)registerDefaults;

/// 「系统与性能」子设置页（挂在元抖设置主界面的「功能」分区里）。
+ (AWESettingBaseViewController *)systemViewController;

@end

NS_ASSUME_NONNULL_END
