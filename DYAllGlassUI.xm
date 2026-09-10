/**
 * DYAll 聚合版 - 液态玻璃统一界面主题
 *
 * 为 DYYYSettingViewController 应用 iOS 26+ 原生液态玻璃(UIGlassEffect)样式；
 * 在 iOS 26 以下系统自动回退为系统材质毛玻璃(UIBlurEffect)。
 * 纯增量修改，不改动 DYYY 原有逻辑。
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DYYYSettingViewController.h"

static BOOL DYAllGlassPrefEnabled(void) {
    // 默认开启液态玻璃；写入 DYAllGlassUIDisabled = YES 可关闭
    return ![[NSUserDefaults standardUserDefaults] boolForKey:@"DYAllGlassUIDisabled"];
}

// iOS 26 液态玻璃效果类，运行时探测，避免在旧系统上引用不存在符号
static UIVisualEffect * _Nullable DYAllGlassEffect(void) {
    Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
    if (glassEffectClass) {
        id effect = [[glassEffectClass alloc] init];
        if (effect) return effect;
    }
    // 回退：iOS 13+ 系统毛玻璃材质（风格接近液态玻璃）
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

%hook DYYYSettingViewController

- (void)viewDidLoad {
    %orig;

    if (!DYAllGlassPrefEnabled()) return;

    UIView *glassView = [[UIVisualEffectView alloc] initWithEffect:DYAllGlassEffect()];
    glassView.frame = self.view.bounds;
    glassView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glassView.userInteractionEnabled = NO;

    // 插到最底层作为玻璃背景，原有 tableView 改为透明以透出玻璃
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

%end
