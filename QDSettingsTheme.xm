/**
 * 轻抖设置页 — 视觉完全重构
 *
 * 仅作用于轻抖自己的设置页（通过关联对象标记隔离，不影响抖音原生设置页）：
 *  - 整页液态玻璃背景（iOS 26+ 原生 UIGlassEffect，旧系统毛玻璃回退）
 *  - 大标题导航「轻抖设置」+ 浅青色调
 *  - 顶部 Hero 渐变头卡：轻抖徽标、版本徽章、模块统计、状态圆点
 *  - 深色模式全适配（动态颜色），约束布局无固定坐标，旋钮不破版
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 抖音内部类局部声明（本文件作用域内让编译器识别 UIViewController 属性）
@interface AWESettingBaseViewController : UIViewController
@end

static BOOL QDIsQingdouPage(UIViewController *vc) {
    return [objc_getAssociatedObject(vc, "qd_is_qingdou_page") boolValue];
}

static UIVisualEffect *QDGlassEffect(void) {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    if (glassClass) {
        id e = [[glassClass alloc] init];
        if (e) return e;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

static UITableView *QDFindTableView(UIView *view, int depth) {
    if (depth > 6) return nil;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UITableView class]]) return (UITableView *)sub;
        UITableView *deep = QDFindTableView(sub, depth + 1);
        if (deep) return deep;
    }
    return nil;
}

static NSInteger QDCountEnabledFeatures(void) {
    NSArray *keys = @[@"DYYYNoAds", @"DYYYisEnableFullScreen", @"DYYYLongPressCopyTextEnabled",
                      @"DYYYisEnableCommentBlur", @"DYYYEnableFloatSpeedButton", @"DYYYEnableFloatClearButton",
                      @"DYKillerGlassTabBar", @"DYKillerCommentGlass", @"DYKillerHideMusicInfo"];
    NSInteger n = 0;
    for (NSString *k in keys) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:k]) n++;
    }
    return n;
}

static UIView *QDBuildHeroHeader(CGFloat width) {
    CGFloat pad = 16, h = 132;
    UIView *hero = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, h + pad)];
    hero.backgroundColor = [UIColor clearColor];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(pad, pad, width - pad * 2, h)];
    card.layer.cornerRadius = 24;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:card];

    // 渐变底：深青 → 靛蓝（深色模式自动加深）
    UIColor *c1 = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.05 green:0.22 blue:0.28 alpha:1]
            : [UIColor colorWithRed:0.10 green:0.55 blue:0.62 alpha:1];
    }];
    UIColor *c2 = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.10 green:0.12 blue:0.32 alpha:1]
            : [UIColor colorWithRed:0.22 green:0.35 blue:0.85 alpha:1];
    }];
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.colors = @[ (id)c1.CGColor, (id)c2.CGColor ];
    grad.startPoint = CGPointMake(0, 0);
    grad.endPoint = CGPointMake(1, 1);
    grad.frame = CGRectMake(0, 0, width - pad * 2, h);
    [card.layer insertSublayer:grad atIndex:0];
    objc_setAssociatedObject(card, "qd_gradient", grad, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 轻抖徽标圆环
    UIView *logo = [[UIView alloc] init];
    logo.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    logo.layer.cornerRadius = 26;
    logo.layer.borderWidth = 1;
    logo.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.45].CGColor;
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:logo];

    UILabel *logoText = [[UILabel alloc] init];
    logoText.text = @"轻";
    logoText.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    logoText.textColor = UIColor.whiteColor;
    logoText.translatesAutoresizingMaskIntoConstraints = NO;
    [logo addSubview:logoText];

    // 标题与副标题
    UILabel *title = [[UILabel alloc] init];
    title.text = @"轻抖";
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightHeavy];
    title.textColor = UIColor.whiteColor;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:title];

    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"抖音增强聚合版 · 液态玻璃界面";
    sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sub];

    UILabel *stat = [[UILabel alloc] init];
    NSInteger enabled = QDCountEnabledFeatures();
    stat.text = [NSString stringWithFormat:@"%ld 个功能模块 · 已开启 %ld 项", (long)9, (long)enabled];
    stat.font = [UIFont systemFontOfSize:12];
    stat.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    stat.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stat];

    // 版本徽章
    UILabel *badge = [[UILabel alloc] init];
    badge.text = @"v3.3.0";
    badge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    badge.textColor = UIColor.whiteColor;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    badge.layer.cornerRadius = 10;
    badge.layer.masksToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:badge];

    // 右上状态点
    UIView *dot = [[UIView alloc] init];
    dot.backgroundColor = [UIColor colorWithRed:0.35 green:0.95 blue:0.6 alpha:1];
    dot.layer.cornerRadius = 5;
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:dot];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:hero.topAnchor constant:pad],
        [card.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:pad],
        [card.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-pad],
        [card.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-pad],
        [logo.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [logo.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [logo.widthAnchor constraintEqualToConstant:52],
        [logo.heightAnchor constraintEqualToConstant:52],
        [logoText.centerXAnchor constraintEqualToAnchor:logo.centerXAnchor],
        [logoText.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:16],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [stat.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [stat.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:6],
        [badge.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [badge.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [badge.widthAnchor constraintEqualToConstant:56],
        [badge.heightAnchor constraintEqualToConstant:20],
        [dot.trailingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:-8],
        [dot.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [dot.widthAnchor constraintEqualToConstant:10],
        [dot.heightAnchor constraintEqualToConstant:10],
    ]];
    return hero;
}

%hook AWESettingBaseViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!QDIsQingdouPage(self)) return;

    self.title = @"轻抖设置";
    self.navigationItem.title = @"轻抖设置";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    if (self.navigationController) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
        self.navigationController.navigationBar.tintColor =
            [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!QDIsQingdouPage(self)) return;
    if (objc_getAssociatedObject(self, "qd_hero_installed")) return;
    objc_setAssociatedObject(self, "qd_hero_installed", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 整页玻璃背景
    UIView *glass = [[UIVisualEffectView alloc] initWithEffect:QDGlassEffect()];
    glass.frame = self.view.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.userInteractionEnabled = NO;
    [self.view insertSubview:glass atIndex:0];

    UITableView *tv = QDFindTableView(self.view, 0);
    if (tv) {
        tv.backgroundColor = [UIColor clearColor];
        tv.backgroundView = nil;

        UIView *hero = QDBuildHeroHeader(tv.bounds.size.width ? tv.bounds.size.width : self.view.bounds.size.width);
        // 用自动布局算出精确高度再落位，避免固定高度在不同字号下破版
        [hero setNeedsLayout];
        [hero layoutIfNeeded];
        CGFloat h = [hero systemLayoutSizeFittingSize:CGSizeMake(tv.bounds.size.width, UILayoutFittingCompressedSizeHeight)]
                        .height;
        if (h < 10) h = hero.frame.size.height;
        hero.frame = CGRectMake(0, 0, tv.bounds.size.width, h);
        tv.tableHeaderView = hero;
    }
}

%end
