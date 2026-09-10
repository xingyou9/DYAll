/**
 * 元抖助手 — 悬浮快捷面板
 *
 * 交互参考抖音助手的"三指长按调出"设计：
 *  - 任意界面三指长按屏幕调出液态玻璃快捷面板
 *  - 面板内为常用功能的快捷开关，拨动即写入设置立即生效
 *  - 提供"全部设置"入口跳转轻抖设置页
 *  - iOS 26+ 使用原生 UIGlassEffect，旧系统回退毛玻璃
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DYYYSettingsHelper.h"
#import "DYYYUtils.h"

#define QD_PREF(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]
#define QD_SET(key, val) [[NSUserDefaults standardUserDefaults] setBool:val forKey:key]

// 拨动后需要刷新全局透明度的键
static NSArray<NSString *> *QDTransparencyKeys(void) {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"DYYYGlobalTransparency", @"DYYYTopBarTransparent", @"DYYYAvatarViewTransparency"];
    });
    return keys;
}

@interface QDAssistantPanelController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@end

static NSArray<NSArray<NSString *> *> *QDPanelGroups(void) {
    static NSArray *groups;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 每组: [标题, 设置键]
        groups = @[
            @[@"无广告", @"DYYYNoAds"],
            @[@"全屏播放", @"DYYYisEnableFullScreen"],
            @[@"长按复制文案", @"DYYYLongPressCopyTextEnabled"],
            @[@"评论区模糊", @"DYYYisEnableCommentBlur"],
            @[@"悬浮倍速按钮", @"DYYYEnableFloatSpeedButton"],
            @[@"悬浮清屏按钮", @"DYYYEnableFloatClearButton"],
            @[@"隐藏弹幕按钮", @"DYYYHideDanmuButton"],
            @[@"隐藏搜索气泡", @"DYYYHideSearchBubble"],
        ];
    });
    return groups;
}

@implementation QDAssistantPanelController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.modalPresentationStyle = UIModalPresentationOverCurrentContext;

    // 玻璃卡片
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect *effect = glassClass ? [[glassClass alloc] init]
                                        : [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:effect];
    card.frame = CGRectMake(28, 0, self.view.bounds.size.width - 56, 0);
    card.layer.cornerRadius = 24;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"元抖助手";
    title.font = [UIFont boldSystemFontOfSize:19];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:title];

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.delegate = self;
    table.dataSource = self;
    table.backgroundColor = [UIColor clearColor];
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.scrollEnabled = NO;
    table.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:table];

    UIButton *allBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [allBtn setTitle:@"打开全部设置" forState:UIControlStateNormal];
    allBtn.titleLabel.font = [UIFont systemFontOfSize:15];
    allBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [allBtn addTarget:self action:@selector(openAllSettings) forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:allBtn];

    CGFloat rowH = 46, rows = QDPanelGroups().count;
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.heightAnchor constraintEqualToConstant:60 + rows * rowH + 54],
        [title.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:16],
        [title.centerXAnchor constraintEqualToAnchor:card.contentView.centerXAnchor],
        [table.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [table.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],
        [table.heightAnchor constraintEqualToConstant:rows * rowH],
        [allBtn.topAnchor constraintEqualToAnchor:table.bottomAnchor constant:6],
        [allBtn.centerXAnchor constraintEqualToAnchor:card.contentView.centerXAnchor],
        [allBtn.heightAnchor constraintEqualToConstant:34],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    [self.view addGestureRecognizer:tap];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return QDPanelGroups().count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 46;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *id = @"QDRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:id];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:id];
        cell.backgroundColor = [UIColor clearColor];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.tag = 100;
        [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
    }
    NSString *title = QDPanelGroups()[indexPath.row][0];
    NSString *key = QDPanelGroups()[indexPath.row][1];
    cell.textLabel.text = title;
    UISwitch *sw = (UISwitch *)cell.accessoryView;
    sw.on = QD_PREF(key);
    objc_setAssociatedObject(sw, "key", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cell;
}

- (void)toggleChanged:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, "key");
    QD_SET(key, sw.on);
    if ([QDTransparencyKeys() containsObject:key]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DYYYGlobalTransparencyDidChangeNotification" object:nil];
    }
}

- (void)openAllSettings {
    [self dismiss];
    UIViewController *root = self.presentingViewController ?: [DYYYUtils getActiveWindow].rootViewController;
    [DYYYSettingsHelper openSettingsWithViewController:root];
}

- (void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

// 三指长按手势挂载
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    for (UIGestureRecognizer *g in self.gestureRecognizers) {
        if ([g isKindOfClass:[UILongPressGestureRecognizer class]] &&
            [(UILongPressGestureRecognizer *)g numberOfTouchesRequired] == 3 &&
            g.view == self) {
            return; // 已挂载，避免重复
        }
    }

    __weak UIWindow *w = self;
    UILongPressGestureRecognizer *lp =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(qd_showAssistant:)];
    lp.numberOfTouchesRequired = 3;
    lp.minimumPressDuration = 0.5;
    [self addGestureRecognizer:lp];
    (void)w;
}

%new
- (void)qd_showAssistant:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;

    UIViewController *root = self.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    if (!root || [root isKindOfClass:[QDAssistantPanelController class]]) return;

    QDAssistantPanelController *panel = [[QDAssistantPanelController alloc] init];
    [root presentViewController:panel animated:NO completion:nil];
}

%end
