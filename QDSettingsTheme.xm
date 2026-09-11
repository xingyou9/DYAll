/**
 * 元抖设置 — 视觉重构（企业级 v2）
 *
 * 只作用于元抖自己的设置页：主页面与所有二级页面都会被
 * DYYYSettingsHelper 打上 `qd_is_qingdou_page` 标记，抖音原生设置页不受影响。
 *
 * 主页面顶部是一张品牌大框：标识、版本徽章、三格运行统计（已开启 / 模块 / 玻璃引擎），
 * 下方一行快捷入口（YTT 液态玻璃 / 系统与性能 / 流畅模式）。
 *
 * 装配时机：全部在 viewWillAppear 完成（push 动画开始前）——之前放在 viewDidAppear，
 * 副标题卡要等动画播完才弹出来，肉眼可见「卡一下」。
 *
 * 全页玻璃底（iOS 26+ UIGlassEffect，旧系统回退系统材质），表格透明以透出玻璃。
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "AwemeHeaders.h"
#import "DYYYConstants.h"
#import "DYYYSettingsHelper.h"
#import "DYYYSettingsIndex.h"
#import "DYYYSystemPages.h"
#import "DYYYCompatibility.h"
#import "DYYYHookManager.h"
#import "DYYYSafetyGuard.h"
#import "DYYYTaskCenter.h"
#import "DYYYDiagnostics.h"
#import "DYYYUtils.h"
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
                  @"DYYYBlockDynamicIsland", @"DYYYSmoothMode", @"YTT.glass", @"YTT.floating",
                  @"DYYYPerfLowMemory", @"DYYYPerfReducePreload", @"DYYYBlockShakeAd",
                  @"DYYYBlockCaptureDetection", @"DYYYBlockTeenModeAlert", @"DYYYSkipSplashAd" ];
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
        g.colors = @[ (id)[UIColor colorWithRed:0.07 green:0.46 blue:0.56 alpha:1].CGColor,
                      (id)[UIColor colorWithRed:0.24 green:0.22 blue:0.68 alpha:1].CGColor,
                      (id)[UIColor colorWithRed:0.13 green:0.13 blue:0.32 alpha:1].CGColor ];
        g.startPoint = CGPointMake(0, 0);
        g.endPoint = CGPointMake(1, 1);
        self.layer.cornerRadius = 24;
        self.layer.masksToBounds = YES;
    }
    return self;
}

@end

#pragma mark - 快捷入口

@interface QDHeroActions : NSObject
@property (nonatomic, weak) UIViewController *owner;
@property (nonatomic, weak) UIButton *smoothBtn;
- (void)refreshSmooth;
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

- (void)toggleSmooth {
    BOOL on = ![QDExtra smoothMode];
    [QDExtra setSmoothMode:on];
    [DYYYUtils showToast:on ? @"流畅模式已开启：预加载与动效已收紧"
                            : @"流畅模式已关闭"];
    [self refreshSmooth];
}

- (void)refreshSmooth {
    BOOL on = [QDExtra smoothMode];
    UIButton *b = self.smoothBtn;
    if (!b) return;
    [b setTitle:on ? @"流畅模式 · 开" : @"流畅模式" forState:UIControlStateNormal];
    b.backgroundColor = on ? [UIColor colorWithRed:0.11 green:0.72 blue:0.47 alpha:0.92]
                           : [UIColor colorWithWhite:1 alpha:0.16];
}

@end

#pragma mark - 主界面搜索（内联浮层，替代独立搜索页）

@interface QDHeroSearch : NSObject <UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, weak) UIViewController *owner;
@property (nonatomic, weak) UITextField *field;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, id> *> *results;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSDictionary<NSString *, void (^)(void)> *categoryBlocks;
- (void)applyQuery:(NSString *)text;
- (void)hidePanel;
@end

static QDHeroSearch *gQDHeroSearch = nil;

@implementation QDHeroSearch

- (void)attachTo:(UIViewController *)owner field:(UITextField *)field {
    self.owner = owner;
    self.field = field;
    self.results = DYYYSettingsSearchIndex();
    self.query = @"";

    [self.panel removeFromSuperview];   // 换设置页实例时避免浮层堆积

    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.layer.cornerRadius = 16;
    panel.layer.masksToBounds = YES;
    panel.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.16 green:0.16 blue:0.18 alpha:1]
            : UIColor.whiteColor;
    }];
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.25;
    panel.layer.shadowRadius = 12;
    panel.layer.shadowOffset = CGSizeMake(0, 4);
    panel.hidden = YES;

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.dataSource = self;
    table.delegate = self;
    table.backgroundColor = UIColor.clearColor;
    table.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    table.layer.cornerRadius = 16;
    table.clipsToBounds = YES;
    [panel addSubview:table];
    self.table = table;
    self.panel = panel;
    [owner.view addSubview:panel];
}

- (void)applyQuery:(NSString *)text {
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    self.query = text;
    if (text.length == 0) {
        [self hidePanel];
        return;
    }
    NSPredicate *predicate = [NSPredicate predicateWithFormat:
        @"title CONTAINS[cd] %@ OR sub CONTAINS[cd] %@ OR id CONTAINS[cd] %@ OR cat CONTAINS[cd] %@",
        text, text, text, text];
    self.results = [DYYYSettingsSearchIndex() filteredArrayUsingPredicate:predicate];
    [self reposition];
    [self.table reloadData];
    self.panel.hidden = NO;
}

- (void)hidePanel {
    self.panel.hidden = YES;
    self.query = @"";
}

- (void)reposition {
    UIViewController *owner = self.owner;
    UITextField *field = self.field;
    if (!owner || !field) return;
    CGRect fieldRect = [field convertRect:field.bounds toView:owner.view];
    CGFloat top = CGRectGetMaxY(fieldRect) + 6;
    CGFloat width = CGRectGetWidth(fieldRect);
    CGFloat height = MIN((CGFloat)self.results.count, 6.0) * 50.0 + 10.0;
    if (self.results.count == 0) height = 54.0;
    height = MIN(height, owner.view.bounds.size.height - top - 16.0);
    self.panel.frame = CGRectMake(CGRectGetMinX(fieldRect), top, width, height);
    self.table.frame = self.panel.bounds;
}

#pragma mark 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.results.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 50.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"QDHeroSearchCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11.5];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    NSDictionary<NSString *, id> *entry = self.results[indexPath.row];
    cell.textLabel.text = entry[@"title"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", entry[@"cat"]];

    // 开关类设置（cellType 37）直接在浮层里给开关
    if ([entry[@"cell"] isKindOfClass:[NSNumber class]] && [entry[@"cell"] integerValue] == 37) {
        NSString *key = entry[@"id"];
        UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
        toggle.transform = CGAffineTransformMakeScale(0.82, 0.82);
        toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
        toggle.onTintColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1];
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        objc_setAssociatedObject(toggle, "qd_hero_search_key", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.accessoryView = toggle;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, "qd_hero_search_key");
    if (key.length == 0) return;
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [DYYYSettingsHelper handleConflictsAndDependenciesForSetting:key isEnabled:sender.isOn];
    [DYYYUtils showToast:[NSString stringWithFormat:@"已%@「%@」", sender.isOn ? @"开启" : @"关闭", key]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary<NSString *, id> *entry = self.results[indexPath.row];
    if ([entry[@"cell"] isKindOfClass:[NSNumber class]] && [entry[@"cell"] integerValue] == 37) return;
    [self hidePanel];
    [self.field resignFirstResponder];
    void (^jumpBlock)(void) = self.categoryBlocks[entry[@"cat"]];
    if (jumpBlock) {
        jumpBlock();
        [DYYYUtils showToast:[NSString stringWithFormat:@"已进入「%@」，请查找「%@」", entry[@"cat"], entry[@"title"]]];
    } else {
        [DYYYUtils showToast:[NSString stringWithFormat:@"「%@」位于「%@」分类", entry[@"title"], entry[@"cat"]]];
    }
}

#pragma mark 输入框 / 交互

- (void)fieldEdited:(UITextField *)sender {
    [self applyQuery:sender.text];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)gr {
    if (self.panel.hidden || !self.owner) return;
    // 点在浮层或搜索框内部不收起，避免打断开关操作
    CGPoint p = [gr locationInView:self.owner.view];
    CGRect fieldRect = [self.field convertRect:self.field.bounds toView:self.owner.view];
    if (CGRectContainsPoint(self.panel.frame, p) || CGRectContainsPoint(fieldRect, p)) return;
    [self hidePanel];
    [self.field resignFirstResponder];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

#pragma mark - 状态大框（主界面直接看状态，不用点进状态中心）

@interface QDHeroStatusTap : NSObject
@property (nonatomic, weak) UIViewController *host;
- (void)openStatusCenter;
@end
@implementation QDHeroStatusTap
- (void)openStatusCenter {
    UIViewController *host = self.host;
    if (host && host.navigationController) {
        UIViewController *page = [[DYYYStatusViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [host.navigationController pushViewController:page animated:YES];
    }
}
@end

static QDHeroStatusTap *gQDStatusTap = nil;

static UIView *QDBuildStatusCard(UIViewController *owner) {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.13];
    card.layer.cornerRadius = 18;
    card.layer.masksToBounds = YES;
    [card.heightAnchor constraintEqualToConstant:196].active = YES;

    UILabel *head = [[UILabel alloc] init];
    head.translatesAutoresizingMaskIntoConstraints = NO;
    head.text = [DYYYSafetyGuard isSafeMode] ? @"⚠️ 安全模式运行中" : @"● 全部模块正常";
    head.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    head.textColor = [DYYYSafetyGuard isSafeMode] ? [UIColor colorWithRed:1 green:0.76 blue:0.33 alpha:1]
                                                  : [UIColor colorWithRed:0.35 green:0.95 blue:0.6 alpha:1];

    NSDictionary<NSString *, NSString *> *env = [DYYYCompatibility environmentInfo];
    NSString *hooks = [NSString stringWithFormat:@"%lu 项", (unsigned long)[DYYYHookManager allRecords].count];
    NSUInteger problem = [DYYYHookManager problemCount];
    if (problem > 0) hooks = [NSString stringWithFormat:@"%@（⚠️ 异常 %lu）", hooks, (unsigned long)problem];

    NSArray<NSArray<NSString *> *> *rows = @[
        @[ @"🛡️", @"Hook 状态", hooks ],
        @[ @"🚀", @"已启用功能", [NSString stringWithFormat:@"%ld 项", (long)[DYYYDiagnostics enabledFeatureCount]] ],
        @[ @"🧊", @"玻璃引擎", QDYTTGlassEngineName() ],
        @[ @"📱", @"系统 / 抖音", [NSString stringWithFormat:@"iOS %@ · 抖音 %@",
            env[@"iOS 版本"] ?: @"?", env[@"抖音版本"] ?: @"?"] ],
        @[ @"📦", @"下载任务", [NSString stringWithFormat:@"今日完成 %lu · 运行中 %lu",
            (unsigned long)[[DYYYTaskCenter shared] finishedCountToday],
            (unsigned long)[[DYYYTaskCenter shared] activeTasks].count] ],
    ];

    UIStackView *vstack = [[UIStackView alloc] init];
    vstack.translatesAutoresizingMaskIntoConstraints = NO;
    vstack.axis = UILayoutConstraintAxisVertical;
    vstack.spacing = 9;

    for (NSArray<NSString *> *row in rows) {
        UIStackView *line = [[UIStackView alloc] init];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.spacing = 7;
        line.alignment = UIStackViewAlignmentCenter;
        line.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *icon = [[UILabel alloc] init];
        icon.text = row[0];
        icon.font = [UIFont systemFontOfSize:12.5];
        [icon.widthAnchor constraintEqualToConstant:20].active = YES;

        UILabel *key = [[UILabel alloc] init];
        key.text = row[1];
        key.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
        key.textColor = [UIColor colorWithWhite:1 alpha:0.72];
        [key setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UILabel *value = [[UILabel alloc] init];
        value.text = row[2];
        value.font = [UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightMedium];
        value.textColor = UIColor.whiteColor;
        value.textAlignment = NSTextAlignmentRight;
        value.lineBreakMode = NSLineBreakByTruncatingMiddle;
        value.adjustsFontSizeToFitWidth = YES;
        value.minimumScaleFactor = 0.8;
        [value setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        [line addArrangedSubview:icon];
        [line addArrangedSubview:key];
        [line addArrangedSubview:value];
        [vstack addArrangedSubview:line];
    }

    [card addSubview:head];
    [card addSubview:vstack];
    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor constraintEqualToAnchor:card.topAnchor constant:13],
        [head.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [vstack.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:9],
        [vstack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [vstack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];

    // 点大框直接进状态中心
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ gQDStatusTap = [[QDHeroStatusTap alloc] init]; });
    gQDStatusTap.host = owner;
    card.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:gQDStatusTap action:@selector(openStatusCenter)];
    [card addGestureRecognizer:tap];
    return card;
}

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

/// 统计大框里的一格：大数字 + 小注释
static UIView *QDStatBlock(NSString *value, NSString *caption) {
    UIView *block = [[UIView alloc] init];
    block.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    block.layer.cornerRadius = 14;
    block.layer.masksToBounds = YES;
    block.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *v = [[UILabel alloc] init];
    v.tag = 771;
    v.text = value;
    v.font = [UIFont monospacedDigitSystemFontOfSize:19 weight:UIFontWeightBold];
    v.textColor = UIColor.whiteColor;
    v.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *c = [[UILabel alloc] init];
    c.text = caption;
    c.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
    c.textColor = [UIColor colorWithWhite:1 alpha:0.68];
    c.translatesAutoresizingMaskIntoConstraints = NO;

    [block addSubview:v];
    [block addSubview:c];
    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:block.topAnchor constant:9],
        [v.centerXAnchor constraintEqualToAnchor:block.centerXAnchor],
        [c.topAnchor constraintEqualToAnchor:v.bottomAnchor constant:1],
        [c.centerXAnchor constraintEqualToAnchor:block.centerXAnchor],
        [c.bottomAnchor constraintEqualToAnchor:block.bottomAnchor constant:-8],
    ]];
    return block;
}

static UIButton *QDQuickButton(NSString *title) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    b.layer.cornerRadius = 14;
    b.layer.masksToBounds = YES;
    return b;
}

static UIView *QDBuildHero(CGFloat width, UIViewController *owner, NSDictionary *categoryBlocks) {
    UIView *root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 564)];
    root.backgroundColor = [UIColor clearColor];

    UIStackView *vstack = [[UIStackView alloc] init];
    vstack.translatesAutoresizingMaskIntoConstraints = NO;
    vstack.axis = UILayoutConstraintAxisVertical;
    vstack.spacing = 10;
    vstack.alignment = UIStackViewAlignmentFill;
    [root addSubview:vstack];

    // ——— 内联搜索框（放在「增强套件」文字上方，直接在主页搜全部功能） ———
    UITextField *search = [[UITextField alloc] init];
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.font = [UIFont systemFontOfSize:14];
    search.textColor = UIColor.whiteColor;
    search.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"🔍 搜索功能（下载 / 倍速 / 透明…）"
            attributes:@{ NSForegroundColorAttributeName : [UIColor colorWithWhite:1 alpha:0.55] }];
    search.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    search.layer.cornerRadius = 14;
    search.layer.masksToBounds = YES;
    search.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 1)];
    search.leftViewMode = UITextFieldViewModeAlways;
    search.clearButtonMode = UITextFieldViewModeWhileEditing;
    search.returnKeyType = UIReturnKeySearch;
    search.autocorrectionType = UITextAutocorrectionTypeNo;
    [search.heightAnchor constraintEqualToConstant:44].active = YES;

    static dispatch_once_t searchOnce;
    dispatch_once(&searchOnce, ^{ gQDHeroSearch = [[QDHeroSearch alloc] init]; });
    gQDHeroSearch.owner = owner;
    gQDHeroSearch.categoryBlocks = categoryBlocks ?: @{};
    [gQDHeroSearch attachTo:owner field:search];
    search.delegate = gQDHeroSearch;
    [search addTarget:gQDHeroSearch action:@selector(fieldEdited:) forControlEvents:UIControlEventEditingChanged];

    // 每个设置页实例都要绑一次「点外部收起」；用关联对象防止同一实例重复绑
    if (!objc_getAssociatedObject(owner.view, "qd_hero_bgtap")) {
        objc_setAssociatedObject(owner.view, "qd_hero_bgtap", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc]
            initWithTarget:gQDHeroSearch action:@selector(backgroundTapped:)];
        bgTap.cancelsTouchesInView = NO;
        [owner.view addGestureRecognizer:bgTap];
    }

    // ——— 品牌大卡 ———
    QDGradientCardView *card = [[QDGradientCardView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card.heightAnchor constraintEqualToConstant:196].active = YES;

    UILabel *badge = [[UILabel alloc] init];
    badge.text = [NSString stringWithFormat:@"v%@", DYYY_VERSION];
    badge.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    badge.textColor = UIColor.whiteColor;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    badge.layer.cornerRadius = 10;
    badge.layer.masksToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:badge];

    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.backgroundColor = [UIColor colorWithRed:0.35 green:0.95 blue:0.6 alpha:1];
    dot.layer.cornerRadius = 4;
    [dot.widthAnchor constraintEqualToConstant:8].active = YES;
    [dot.heightAnchor constraintEqualToConstant:8].active = YES;
    [card addSubview:dot];

    UIStackView *idRow = [[UIStackView alloc] init];
    idRow.translatesAutoresizingMaskIntoConstraints = NO;
    idRow.axis = UILayoutConstraintAxisHorizontal;
    idRow.spacing = 13;
    idRow.alignment = UIStackViewAlignmentCenter;
    [card addSubview:idRow];

    UIView *logo = [[UIView alloc] init];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    logo.layer.cornerRadius = 26;
    logo.layer.borderWidth = 1;
    logo.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
    [logo.widthAnchor constraintEqualToConstant:52].active = YES;
    [logo.heightAnchor constraintEqualToConstant:52].active = YES;

    UILabel *logoText = [[UILabel alloc] init];
    logoText.translatesAutoresizingMaskIntoConstraints = NO;
    logoText.text = @"元";
    logoText.font = [UIFont systemFontOfSize:25 weight:UIFontWeightHeavy];
    logoText.textColor = UIColor.whiteColor;
    logoText.textAlignment = NSTextAlignmentCenter;
    [logo addSubview:logoText];

    UIStackView *texts = [[UIStackView alloc] init];
    texts.translatesAutoresizingMaskIntoConstraints = NO;
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 2;
    texts.alignment = UIStackViewAlignmentLeading;

    UILabel *title = [[UILabel alloc] init];
    title.text = @"元抖";
    title.font = [UIFont systemFontOfSize:25 weight:UIFontWeightHeavy];
    title.textColor = UIColor.whiteColor;

    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"元抖增强套件 · 完全适配 iOS 26/27";
    sub.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.75];

    [texts addArrangedSubview:title];
    [texts addArrangedSubview:sub];

    [idRow addArrangedSubview:logo];
    [idRow addArrangedSubview:texts];

    // ——— 三格统计 ———
    NSInteger enabled = QDCountEnabled();
    UIStackView *stats = [[UIStackView alloc] init];
    stats.translatesAutoresizingMaskIntoConstraints = NO;
    stats.axis = UILayoutConstraintAxisHorizontal;
    stats.spacing = 8;
    stats.distribution = UIStackViewDistributionFillEqually;
    [stats.heightAnchor constraintEqualToConstant:62].active = YES;

    [stats addArrangedSubview:QDStatBlock([NSString stringWithFormat:@"%ld 项", (long)enabled], @"已开启")];
    [stats addArrangedSubview:QDStatBlock(@"8 大", @"功能模块")];
    [stats addArrangedSubview:QDStatBlock(QDYTTGlassNativeAvailable() ? @"原生" : @"兼容", @"玻璃引擎")];

    [card addSubview:stats];

    [NSLayoutConstraint activateConstraints:@[
        [badge.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [badge.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [badge.widthAnchor constraintGreaterThanOrEqualToConstant:52],
        [badge.heightAnchor constraintEqualToConstant:20],

        [dot.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [dot.trailingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:-8],

        [idRow.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [idRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [idRow.trailingAnchor constraintLessThanOrEqualToAnchor:dot.leadingAnchor constant:-8],

        [logoText.centerXAnchor constraintEqualToAnchor:logo.centerXAnchor],
        [logoText.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],

        [stats.topAnchor constraintEqualToAnchor:idRow.bottomAnchor constant:16],
        [stats.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [stats.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
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
    UIButton *smoothBtn = QDQuickButton(@"流畅模式");
    [smoothBtn addTarget:actions action:@selector(toggleSmooth) forControlEvents:UIControlEventTouchUpInside];
    actions.smoothBtn = smoothBtn;
    [actions refreshSmooth];
    [quick addArrangedSubview:yttBtn];
    [quick addArrangedSubview:sysBtn];
    [quick addArrangedSubview:smoothBtn];

    // ——— 提示条 ———
    UILabel *tip = [[UILabel alloc] init];
    tip.text = @"三指长按屏幕可随时唤出「元抖助手」快捷面板";
    tip.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    tip.textColor = UIColor.secondaryLabelColor;
    tip.textAlignment = NSTextAlignmentCenter;

    [vstack addArrangedSubview:search];
    [vstack addArrangedSubview:card];
    [vstack addArrangedSubview:QDBuildStatusCard(owner)];
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

static void QDThemeInstall(UIViewController *self) {
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
    if (w < 10) w = [UIScreen mainScreen].bounds.size.width;
    BOOL isRoot = (self.navigationController.viewControllers.firstObject == self);
    NSString *pageTitle = objc_getAssociatedObject(self, "qd_page_title");
    if (pageTitle.length == 0) pageTitle = self.title;
    if (pageTitle.length == 0) pageTitle = @"";
    if (isRoot) {
        NSDictionary *blocks = objc_getAssociatedObject(self, "qd_category_blocks");
        tv.tableHeaderView = QDBuildHero(w, self, blocks);
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

    // 关键：装配放在这里（push 动画开始前），二级页副标题不再「卡一下才出来」。
    QDThemeInstall(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!QDIsQingdouPage(self)) return;
    // 兜底：个别页面 viewWillAppear 时表格还没挂上，这里补一次（幂等）。
    QDThemeInstall(self);
}

%end
