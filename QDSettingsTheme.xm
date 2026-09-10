/**
 * 元抖设置 — 视觉重构（企业级）
 *
 * 只作用于元抖自己的设置页：主页面与所有二级页面都会被
 * DYYYSettingsHelper 打上 `qd_is_qingdou_page` 标记，抖音原生设置页不受影响。
 *
 * 主页面顶部是一张 Hero 卡：品牌标识、版本徽章、运行统计、状态点，
 * 下方一行快捷入口（YTT 液态玻璃 / 系统与性能）。二级页面给一张轻量标题卡。
 *
 * 全页玻璃底（iOS 26+ UIGlassEffect，旧系统回退系统材质），表格透明以透出玻璃。
 * 所有布局走 UIStackView + 约束，深色模式自动适配，无固定坐标破版风险。
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "AwemeHeaders.h"
#import "DYYYConstants.h"
#import "DYYYSettingsHelper.h"
#import "QDGlassTabBar.h"
#import "QDExtra.h"

#define QD_KEEP_GLASS_TAG 993344

#pragma mark - 材质

static UIVisualEffect *QDThemeGlassEffect(void) {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    if (glassClass) {
        @try {
            id effect = nil;
            SEL styleSel = NSSelectorFromString(@"effectWithStyle:");
            if ([glassClass respondsToSelector:styleSel]) {
                effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)((id)glassClass, styleSel, (NSInteger)0);
            }
            if (!effect) effect = [[glassClass alloc] init];
            if (effect) return effect;
        } @catch (__unused NSException *e) {
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

static UIColor *QDThemeAccent(void) {
    return [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1];
}

static BOOL QDIsQingdouPage(UIViewController *vc) {
    return [objc_getAssociatedObject(vc, "qd_is_qingdou_page") boolValue];
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

#pragma mark - 统计

static NSArray<NSString *> *QDStatKeys(void) {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[ @"DYYYNoAds", @"DYYYisEnableFullScreen", @"DYYYLongPressCopyTextEnabled",
                  @"DYYYisEnableCommentBlur", @"DYYYEnableFloatSpeedButton", @"DYYYEnableFloatClearButton",
                  @"DYYYHideDanmuButton", @"DYYYHideSearchBubble", @"DYYYisSkipLive",
                  @"DYYYBlockDynamicIsland", @"YTT.glass" ];
    });
    return keys;
}

static NSInteger QDCountEnabled(void) {
    NSInteger n = 0;
    for (NSString *k in QDStatKeys()) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:k]) n++;
    }
    return n;
}

#pragma mark - 渐变卡

@interface QDGradientCardView : UIView
@end

@implementation QDGradientCardView

+ (Class)layerClass {
    return [CAGradientLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        CAGradientLayer *g = (CAGradientLayer *)self.layer;
        g.colors = @[ (id)[UIColor colorWithRed:0.09 green:0.52 blue:0.60 alpha:1].CGColor,
                      (id)[UIColor colorWithRed:0.20 green:0.33 blue:0.83 alpha:1].CGColor ];
        g.startPoint = CGPointMake(0, 0);
        g.endPoint = CGPointMake(1, 1);
        self.layer.cornerRadius = 22;
        self.layer.masksToBounds = YES;
    }
    return self;
}

@end

#pragma mark - 快捷入口

@interface QDHeroActions : NSObject
@property (nonatomic, weak) UIViewController *owner;
@end

@implementation QDHeroActions

- (void)openYTT {
    UIViewController *vc = self.owner;
    if (!vc) return;
    UIViewController *page = [[NSClassFromString(@"QDYTTPageController") alloc] init];
    if (page) [vc.navigationController pushViewController:page animated:YES];
}

- (void)openSystem {
    UIViewController *vc = self.owner;
    if (!vc) return;
    UIViewController *page = [QDExtra systemViewController];
    if (page) [vc.navigationController pushViewController:page animated:YES];
}

@end

#pragma mark - Hero

static UILabel *QDChip(NSString *value, NSString *label) {
    UILabel *l = [[UILabel alloc] init];
    l.text = [NSString stringWithFormat:@"%@  %@", value, label];
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    l.textColor = [UIColor colorWithWhite:1 alpha:0.9];
    l.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    l.layer.cornerRadius = 9;
    l.layer.masksToBounds = YES;
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

static UIButton *QDQuickButton(NSString *title) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    b.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1 alpha:0.08]
                                                               : [UIColor colorWithWhite:1 alpha:0.85];
    }];
    b.layer.cornerRadius = 14;
    b.layer.masksToBounds = YES;
    return b;
}

static UIView *QDBuildHero(CGFloat width, UIViewController *owner) {
    UIView *root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 258)];
    root.backgroundColor = [UIColor clearColor];

    UIStackView *vstack = [[UIStackView alloc] init];
    vstack.translatesAutoresizingMaskIntoConstraints = NO;
    vstack.axis = UILayoutConstraintAxisVertical;
    vstack.spacing = 10;
    vstack.alignment = UIStackViewAlignmentFill;
    [root addSubview:vstack];

    // ——— 卡片 ———
    QDGradientCardView *card = [[QDGradientCardView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card.heightAnchor constraintEqualToConstant:150].active = YES;

    UIStackView *hstack = [[UIStackView alloc] init];
    hstack.translatesAutoresizingMaskIntoConstraints = NO;
    hstack.axis = UILayoutConstraintAxisHorizontal;
    hstack.spacing = 14;
    hstack.alignment = UIStackViewAlignmentCenter;
    [card addSubview:hstack];

    UIView *logo = [[UIView alloc] init];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    logo.layer.cornerRadius = 28;
    logo.layer.borderWidth = 1;
    logo.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
    [logo.widthAnchor constraintEqualToConstant:56].active = YES;
    [logo.heightAnchor constraintEqualToConstant:56].active = YES;

    UILabel *logoText = [[UILabel alloc] init];
    logoText.translatesAutoresizingMaskIntoConstraints = NO;
    logoText.text = @"元";
    logoText.font = [UIFont systemFontOfSize:27 weight:UIFontWeightHeavy];
    logoText.textColor = UIColor.whiteColor;
    logoText.textAlignment = NSTextAlignmentCenter;
    [logo addSubview:logoText];

    UIStackView *texts = [[UIStackView alloc] init];
    texts.translatesAutoresizingMaskIntoConstraints = NO;
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 3;
    texts.alignment = UIStackViewAlignmentLeading;

    UILabel *title = [[UILabel alloc] init];
    title.text = @"元抖";
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy];
    title.textColor = UIColor.whiteColor;

    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"抖音增强套件 · Douyin Enhancement Suite";
    sub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.75];

    UIStackView *chips = [[UIStackView alloc] init];
    chips.axis = UILayoutConstraintAxisHorizontal;
    chips.spacing = 6;
    chips.alignment = UIStackViewAlignmentCenter;
    NSInteger enabled = QDCountEnabled();
    [chips addArrangedSubview:QDChip([NSString stringWithFormat:@"%ld", (long)enabled], @"已开启")];
    [chips addArrangedSubview:QDChip(@"6", @"功能模块")];
    [chips addArrangedSubview:QDChip(QDYTTGlassNativeAvailable() ? @"原生" : @"降级", @"玻璃引擎")];

    [texts addArrangedSubview:title];
    [texts addArrangedSubview:sub];
    [texts addArrangedSubview:chips];

    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *badge = [[UILabel alloc] init];
    badge.text = [NSString stringWithFormat:@" %@ ", DYYY_VERSION];
    badge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    badge.textColor = UIColor.whiteColor;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    badge.layer.cornerRadius = 10;
    badge.layer.masksToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.backgroundColor = [UIColor colorWithRed:0.35 green:0.95 blue:0.6 alpha:1];
    dot.layer.cornerRadius = 5;
    [dot.widthAnchor constraintEqualToConstant:10].active = YES;
    [dot.heightAnchor constraintEqualToConstant:10].active = YES;

    UIStackView *right = [[UIStackView alloc] initWithArrangedSubviews:@[ dot, badge ]];
    right.axis = UILayoutConstraintAxisVertical;
    right.spacing = 8;
    right.alignment = UIStackViewAlignmentTrailing;
    right.translatesAutoresizingMaskIntoConstraints = NO;

    [hstack addArrangedSubview:logo];
    [hstack addArrangedSubview:texts];
    [hstack addArrangedSubview:spacer];
    [hstack addArrangedSubview:right];

    [NSLayoutConstraint activateConstraints:@[
        [hstack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [hstack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [hstack.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [logoText.centerXAnchor constraintEqualToAnchor:logo.centerXAnchor],
        [logoText.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:60],
        [badge.heightAnchor constraintEqualToConstant:20],
    ]];

    // ——— 快捷入口 ———
    UIStackView *quick = [[UIStackView alloc] init];
    quick.translatesAutoresizingMaskIntoConstraints = NO;
    quick.axis = UILayoutConstraintAxisHorizontal;
    quick.spacing = 10;
    quick.distribution = UIStackViewDistributionFillEqually;
    [quick.heightAnchor constraintEqualToConstant:46].active = YES;

    static QDHeroActions *actions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ actions = [[QDHeroActions alloc] init]; });
    actions.owner = owner;

    UIButton *yttBtn = QDQuickButton(@"YTT 液态玻璃");
    [yttBtn addTarget:actions action:@selector(openYTT) forControlEvents:UIControlEventTouchUpInside];
    UIButton *sysBtn = QDQuickButton(@"系统与性能");
    [sysBtn addTarget:actions action:@selector(openSystem) forControlEvents:UIControlEventTouchUpInside];
    [quick addArrangedSubview:yttBtn];
    [quick addArrangedSubview:sysBtn];

    // ——— 提示条 ———
    UILabel *tip = [[UILabel alloc] init];
    tip.text = @"三指长按屏幕可随时唤出「元抖助手」快捷面板";
    tip.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    tip.textColor = UIColor.secondaryLabelColor;
    tip.textAlignment = NSTextAlignmentCenter;

    [vstack addArrangedSubview:card];
    [vstack addArrangedSubview:quick];
    [vstack addArrangedSubview:tip];

    // 只钉 top / 左右，底边留给内容自然高度，避免与容器固定高度打架
    [NSLayoutConstraint activateConstraints:@[
        [vstack.topAnchor constraintEqualToAnchor:root.topAnchor constant:14],
        [vstack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],
        [vstack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],
    ]];

    return root;
}

static UIView *QDBuildSubHeader(CGFloat width, NSString *title, NSString *subtitle) {
    UIView *root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 66)];
    root.backgroundColor = [UIColor clearColor];

    UIStackView *v = [[UIStackView alloc] init];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.axis = UILayoutConstraintAxisVertical;
    v.spacing = 2;
    [root addSubview:v];

    UILabel *t = [[UILabel alloc] init];
    t.text = title;
    t.font = [UIFont systemFontOfSize:23 weight:UIFontWeightBold];
    t.textColor = UIColor.labelColor;

    UILabel *s = [[UILabel alloc] init];
    s.text = subtitle;
    s.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    s.textColor = UIColor.secondaryLabelColor;

    [v addArrangedSubview:t];
    [v addArrangedSubview:s];

    [NSLayoutConstraint activateConstraints:@[
        [v.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:18],
        [v.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-18],
        [v.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-6],
    ]];
    return root;
}

#pragma mark - Hook

%hook AWESettingBaseViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!QDIsQingdouPage(self)) return;

    BOOL isRoot = (self.navigationController.viewControllers.firstObject == self);
    NSString *pageTitle = objc_getAssociatedObject(self, "qd_page_title");
    if (pageTitle.length == 0) pageTitle = self.title;
    if (pageTitle.length == 0) pageTitle = @"";
    self.title = isRoot ? @"元抖设置" : pageTitle;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    if (self.navigationController) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
        self.navigationController.navigationBar.tintColor = QDThemeAccent();
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!QDIsQingdouPage(self)) return;
    if (objc_getAssociatedObject(self, "qd_theme_installed")) return;
    objc_setAssociatedObject(self, "qd_theme_installed", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 整页玻璃底（打 tag，避免被「关闭毛玻璃」误伤）
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:QDThemeGlassEffect()];
    glass.frame = self.view.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.userInteractionEnabled = NO;
    glass.tag = QD_KEEP_GLASS_TAG;
    [self.view insertSubview:glass atIndex:0];

    UITableView *tv = QDFindTableView(self.view, 0);
    if (!tv) return;
    tv.backgroundColor = [UIColor clearColor];
    tv.backgroundView = nil;
    tv.separatorColor = [UIColor separatorColor];

    CGFloat w = tv.bounds.size.width > 10 ? tv.bounds.size.width : self.view.bounds.size.width;
    BOOL isRoot = (self.navigationController.viewControllers.firstObject == self);
    if (isRoot) {
        tv.tableHeaderView = QDBuildHero(w, self);
    } else {
        tv.tableHeaderView = QDBuildSubHeader(w, pageTitle, @"元抖 · 抖音增强套件");
    }

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 48)];
    UILabel *f = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, w, 24)];
    f.text = [NSString stringWithFormat:@"元抖 %@  ·  设置即时生效", DYYY_VERSION];
    f.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    f.textColor = UIColor.tertiaryLabelColor;
    f.textAlignment = NSTextAlignmentCenter;
    [footer addSubview:f];
    tv.tableFooterView = footer;
}

%end
