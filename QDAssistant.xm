/**
 * 元抖助手 — 三指长按悬浮快捷面板
 *
 * 交互：任意界面三指长按 0.5s 调出；面板内为常用功能开关，拨动即写入偏好、立即生效。
 *
 * 历史 bug（首页三指长按只看到一片灰、什么都没有）的两个根因，改动前请勿还原：
 *   1. presentationStyle 写在 viewDidLoad 里 —— 太晚了。present 时系统已经按默认样式
 *      把 presentingViewController 的 view 移出层级，于是只剩一层灰色遮罩。
 *      必须写在 init 里（present 之前）。
 *   2. 玻璃卡片没有宽度约束 —— 只给了 centerX/centerY/height，UIVisualEffectView 没有
 *      intrinsicContentSize，宽度被解成 0，卡片连同内部所有控件一起塌成一条线。
 *      现在用 widthAnchor = view.width - 56 明确给定。
 *
 * 视觉：iOS 26+ 原生 UIGlassEffect，旧系统回退系统材质毛玻璃；深色模式自动适配。
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "DYYYSettingsHelper.h"
#import "DYYYUtils.h"

#define QD_PREF(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]
#define QD_SET(key, val) [[NSUserDefaults standardUserDefaults] setBool:val forKey:key]

#pragma mark - 玻璃材质

static UIVisualEffect *QDAssistantGlassEffect(void) {
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

#pragma mark - 面板数据

// 每行: [标题, 偏好键]
static NSArray<NSArray<NSString *> *> *QDPanelRows(void) {
    static NSArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[
            @[ @"无广告模式", @"DYYYNoAds" ],
            @[ @"全屏播放", @"DYYYisEnableFullScreen" ],
            @[ @"长按复制文案", @"DYYYLongPressCopyTextEnabled" ],
            @[ @"评论区模糊", @"DYYYisEnableCommentBlur" ],
            @[ @"悬浮倍速按钮", @"DYYYEnableFloatSpeedButton" ],
            @[ @"悬浮清屏按钮", @"DYYYEnableFloatClearButton" ],
            @[ @"隐藏弹幕按钮", @"DYYYHideDanmuButton" ],
            @[ @"隐藏搜索气泡", @"DYYYHideSearchBubble" ],
            @[ @"屏蔽灵动岛", @"DYYYBlockDynamicIsland" ],
            @[ @"YTT 液态玻璃", @"YTT.glass" ],
        ];
    });
    return rows;
}

static NSArray<NSString *> *QDTransparencyKeys(void) {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[ @"DYYYGlobalTransparency", @"DYYYTopBarTransparent", @"DYYYAvatarViewTransparency" ];
    });
    return keys;
}

#pragma mark - 面板控制器

@interface QDAssistantPanelController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UIVisualEffectView *card;
@property (nonatomic, strong) UITableView *table;
@end

@implementation QDAssistantPanelController

- (instancetype)init {
    if ((self = [super init])) {
        // 关键：present 之前就定好，否则 presentingVC 的 view 会被移出层级 → 一片灰
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];

    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:QDAssistantGlassEffect()];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 28;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.tag = 993344;
    [self.view addSubview:card];
    self.card = card;
    UIView *content = card.contentView;

    // 顶部徽标
    UIView *badge = [[UIView alloc] init];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:0.85];
    badge.layer.cornerRadius = 17;
    [content addSubview:badge];

    UILabel *badgeText = [[UILabel alloc] init];
    badgeText.translatesAutoresizingMaskIntoConstraints = NO;
    badgeText.text = @"元";
    badgeText.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    badgeText.textColor = UIColor.whiteColor;
    badgeText.textAlignment = NSTextAlignmentCenter;
    [badge addSubview:badgeText];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"元抖助手";
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    title.textColor = UIColor.labelColor;
    [content addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"常用开关 · 拨动即时生效";
    subtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    subtitle.textColor = UIColor.secondaryLabelColor;
    [content addSubview:subtitle];

    CGFloat rowH = 46;
    CGFloat rows = (CGFloat)QDPanelRows().count;

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.delegate = self;
    table.dataSource = self;
    table.backgroundColor = [UIColor clearColor];
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.scrollEnabled = NO;
    table.rowHeight = rowH;
    [content addSubview:table];
    self.table = table;

    UIButton *settingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    settingsBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [settingsBtn setTitle:@"打开全部设置" forState:UIControlStateNormal];
    settingsBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    settingsBtn.layer.cornerRadius = 17;
    settingsBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:0.18];
    [settingsBtn addTarget:self action:@selector(openAllSettings) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:settingsBtn];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn setTitle:@"关闭" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    [closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:closeBtn];

    CGFloat cardH = 78 + rows * rowH + 58;

    [NSLayoutConstraint activateConstraints:@[
        // 关键：给卡片一个明确宽度，否则 UIVisualEffectView 没有固有尺寸会被解成 0
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-56],
        [card.heightAnchor constraintEqualToConstant:cardH],

        [badge.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [badge.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [badge.widthAnchor constraintEqualToConstant:34],
        [badge.heightAnchor constraintEqualToConstant:34],
        [badgeText.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [badgeText.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],

        [title.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:11],
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:17],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],

        [table.topAnchor constraintEqualToAnchor:content.topAnchor constant:70],
        [table.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [table.heightAnchor constraintEqualToConstant:rows * rowH],

        [settingsBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [settingsBtn.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
        [settingsBtn.topAnchor constraintEqualToAnchor:table.bottomAnchor constant:6],
        [settingsBtn.heightAnchor constraintEqualToConstant:38],

        [closeBtn.topAnchor constraintEqualToAnchor:settingsBtn.bottomAnchor constant:2],
        [closeBtn.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [closeBtn.heightAnchor constraintEqualToConstant:26],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onBackdropTap:)];
    tap.delegate = (id<UIGestureRecognizerDelegate>)self;
    [self.view addGestureRecognizer:tap];

    // 入场：轻微缩放 + 淡入，出场由系统 cross dissolve 处理
    card.transform = CGAffineTransformMakeScale(0.92, 0.92);
    card.alpha = 0;
    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                       card.transform = CGAffineTransformIdentity;
                       card.alpha = 1;
                     }
                     completion:nil];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // 只有点在卡片外面才关闭
    CGPoint p = [touch locationInView:self.card];
    return !(p.x >= 0 && p.y >= 0 && p.x <= self.card.bounds.size.width && p.y <= self.card.bounds.size.height);
}

- (void)onBackdropTap:(__unused UITapGestureRecognizer *)g {
    [self dismiss];
}

#pragma mark - 表格

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    return (NSInteger)QDPanelRows().count;
}

- (CGFloat)tableView:(__unused UITableView *)tableView heightForRowAtIndexPath:(__unused NSIndexPath *)indexPath {
    return 46;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"QDAssistantRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        cell.textLabel.textColor = UIColor.labelColor;

        UISwitch *sw = [[UISwitch alloc] init];
        sw.onTintColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1];
        [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }

    NSArray<NSString *> *row = QDPanelRows()[(NSUInteger)indexPath.row];
    cell.textLabel.text = row[0];
    UISwitch *sw = (UISwitch *)cell.accessoryView;
    sw.on = QD_PREF(row[1]);
    objc_setAssociatedObject(sw, "qd_pref_key", row[1], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cell;
}

- (void)toggleChanged:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, "qd_pref_key");
    if (!key) return;
    QD_SET(key, sw.on);
    if ([QDTransparencyKeys() containsObject:key]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DYYYGlobalTransparencyDidChangeNotification" object:nil];
    }
    [DYYYUtils showToast:[NSString stringWithFormat:@"%@ 已%@", key, sw.on ? @"开启" : @"关闭"]];
}

#pragma mark - 动作

- (void)openAllSettings {
    UIViewController *root = self.presentingViewController;
    if (!root) root = [UIApplication sharedApplication].keyWindow.rootViewController;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                               if (root) [DYYYSettingsHelper openSettingsWithViewController:root];
                             }];
}

- (void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - 三指长按手势

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    for (UIGestureRecognizer *g in self.gestureRecognizers) {
        if ([g isKindOfClass:[UILongPressGestureRecognizer class]] &&
            [(UILongPressGestureRecognizer *)g numberOfTouchesRequired] == 3) {
            return; // 已挂载
        }
    }

    UILongPressGestureRecognizer *lp =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(qd_showAssistant:)];
    lp.numberOfTouchesRequired = 3;
    lp.minimumPressDuration = 0.5;
    lp.cancelsTouchesInView = NO;
    [self addGestureRecognizer:lp];
}

%new
- (void)qd_showAssistant:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;

    UIViewController *root = self.rootViewController;
    NSInteger guard = 0;
    while (root.presentedViewController && guard++ < 8) {
        root = root.presentedViewController;
    }
    if (!root) return;
    if ([root isKindOfClass:[QDAssistantPanelController class]]) return;
    if (root.presentedViewController) return; // 已有弹层时不叠加

    QDAssistantPanelController *panel = [[QDAssistantPanelController alloc] init];
    [root presentViewController:panel animated:YES completion:nil];
}

%end
