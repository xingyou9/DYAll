/**
 * DYAll / 元抖 — 液态玻璃主题界面
 *
 * 对设置界面做整体视觉重构，与原版 DYYY 明显区分：
 *  - iOS 26+ 使用系统原生液态玻璃 UIGlassEffect 作为全局背景
 *  - 旧系统回退为系统材质毛玻璃
 *  - 导航标题改为"元抖"，配浅青色调强调色
 *  - 表格透明化以透出玻璃层
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DYYYSettingViewController.h"

static BOOL DYAllGlassPrefEnabled(void) {
    // 默认开启液态玻璃；写入 DYAllGlassUIDisabled = YES 可关闭
    return ![[NSUserDefaults standardUserDefaults] boolForKey:@"DYAllGlassUIDisabled"];
}

// iOS 26 液态玻璃效果类，运行时探测，避免旧系统引用不存在的符号
static UIVisualEffect * _Nullable DYAllGlassEffect(void) {
    Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
    if (glassEffectClass) {
        id effect = [[glassEffectClass alloc] init];
        if (effect) return effect;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

%hook DYYYSettingViewController

- (void)viewDidLoad {
    %orig;

    self.title = @"元抖";
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1.0];

    if (!DYAllGlassPrefEnabled()) return;

    UIView *glassView = [[UIVisualEffectView alloc] initWithEffect:DYAllGlassEffect()];
    glassView.frame = self.view.bounds;
    glassView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glassView.userInteractionEnabled = NO;
    [self.view insertSubview:glassView atIndex:0];

    for (UIView *sub in self.view.subviews) {
        if (sub == glassView) continue;
        if ([sub isKindOfClass:[UITableView class]]) {
            UITableView *tv = (UITableView *)sub;
            tv.backgroundColor = [UIColor clearColor];
            tv.backgroundView = nil;
        }
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
}

%end
