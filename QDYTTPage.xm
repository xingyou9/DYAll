/**
 * YTT · 液态玻璃适配 — 元抖设置内嵌面板
 *
 * 与底栏引擎 QDGlassTabBar 共用同一批偏好键（YTT.glass / clear / gradient / capsule / extend），
 * 开关状态与 YTT 原生面板完全互通；每次拨动会立刻触发一次重绘。
 *
 * 页面提供：
 *  - 玻璃头部卡：引擎类型（原生 UIGlassEffect / 降级毛玻璃）+ 底栏接管状态实时显示
 *  - 五个功能开关，带副标题说明
 *  - 状态区：实时显示引擎、接管类名、结果，方便排查「为什么没效果」
 *  - 立即重绘：手动触发一次底栏接管
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "QDGlassTabBar.h"
#import "DYYYUtils.h"

#pragma mark - 规格

// [标题, 副标题, 偏好键]
static NSArray<NSArray<NSString *> *> *QDYTTItems(void) {
    static NSArray *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        items = @[
            @[ @"液态玻璃", @"把抖音底栏换成官方液态玻璃材质（总开关）", @"YTT.glass" ],
            @[ @"悬浮玻璃底栏", @"iOS 26+ 用系统原生胶囊底栏：选中项放大滑动、加号保持原位", @"YTT.floating" ],
            @[ @"视频透出底栏", @"作品画面延伸到底栏后面，底栏不再是黑色一块", @"YTT.extend" ],
            @[ @"摘掉压暗渐变", @"移除盖在玻璃上的黑色渐变，通透感更强", @"YTT.gradient" ],
            @[ @"清除底栏着色", @"Clear 档：进一步清掉底栏自身的着色层", @"YTT.clear" ],
            @[ @"玻璃胶囊跟随", @"切换 Tab 时玻璃胶囊跟随滑动（仅旧引擎）", @"YTT.capsule" ],
        ];
    });
    return items;
}

#pragma mark - 头部卡

static UIView *QDYTTBuildHeader(CGFloat width) {
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 132)];
    wrap.backgroundColor = [UIColor clearColor];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 12, width - 32, 108)];
    card.layer.cornerRadius = 22;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:card];

    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.colors = @[ (id)[UIColor colorWithRed:0.10 green:0.55 blue:0.62 alpha:1].CGColor,
                     (id)[UIColor colorWithRed:0.22 green:0.35 blue:0.85 alpha:1].CGColor ];
    grad.startPoint = CGPointMake(0, 0);
    grad.endPoint = CGPointMake(1, 1);
    grad.frame = CGRectMake(0, 0, width - 32, 108);
    [card.layer insertSublayer:grad atIndex:0];

    UIView *badge = [[UIView alloc] init];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    badge.layer.cornerRadius = 20;
    [card addSubview:badge];

    UILabel *badgeText = [[UILabel alloc] init];
    badgeText.translatesAutoresizingMaskIntoConstraints = NO;
    badgeText.text = @"Y";
    badgeText.font = [UIFont systemFontOfSize:19 weight:UIFontWeightHeavy];
    badgeText.textColor = UIColor.whiteColor;
    badgeText.textAlignment = NSTextAlignmentCenter;
    [badge addSubview:badgeText];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"YTT · 液态玻璃适配";
    title.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    [card addSubview:title];

    UILabel *engine = [[UILabel alloc] init];
    engine.translatesAutoresizingMaskIntoConstraints = NO;
    engine.text = QDYTTGlassEngineName();
    engine.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    engine.textColor = [UIColor colorWithWhite:1 alpha:0.92];
    [card addSubview:engine];

    UILabel *status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.text = QDYTTGlassBarStatus();
    status.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    status.textColor = [UIColor colorWithWhite:1 alpha:0.72];
    status.numberOfLines = 2;
    [card addSubview:status];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:12],
        [card.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-16],
        [card.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-12],

        [badge.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [badge.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:40],
        [badge.heightAnchor constraintEqualToConstant:40],
        [badgeText.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [badgeText.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],

        [title.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:13],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:22],
        [engine.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [engine.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [status.topAnchor constraintEqualToAnchor:engine.bottomAnchor constant:3],
        [status.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];

    return wrap;
}

#pragma mark - 控制器

@interface QDYTTPageController : UITableViewController
@end

@implementation QDYTTPageController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"YTT";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    if (self.navigationController) {
        self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1];
    }
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 0);

    CGFloat w = self.tableView.bounds.size.width > 10 ? self.tableView.bounds.size.width
                                                     : [UIScreen mainScreen].bounds.size.width;
    self.tableView.tableHeaderView = QDYTTBuildHeader(w);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark 数据源

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 3;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"功能开关" : (section == 1 ? @"运行状态" : @"操作");
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"开关与 YTT 独立插件共用同一批偏好键，状态完全互通；拨动后立即重绘底栏。";
    }
    if (section == 1) {
        return @"若显示「未接管」，请回到首页停留 1–2 秒再返回本页查看。";
    }
    return nil;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)QDYTTItems().count : (section == 1 ? 3 : 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        static NSString *swId = @"QDYTTSwitch";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:swId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:swId];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [[UISwitch alloc] init];
            sw.onTintColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1];
            [sw addTarget:self action:@selector(qdSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        NSArray<NSString *> *item = QDYTTItems()[(NSUInteger)indexPath.row];
        cell.textLabel.text = item[0];
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        cell.detailTextLabel.text = item[1];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        cell.detailTextLabel.numberOfLines = 2;
        if ([UIImage respondsToSelector:@selector(systemImageNamed:)]) {
            cell.imageView.image = [UIImage systemImageNamed:@"sparkles"];
            cell.imageView.tintColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1];
        }

        UISwitch *sw = (UISwitch *)cell.accessoryView;
        sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:item[2]];
        objc_setAssociatedObject(sw, "qd_ytt_key", item[2], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return cell;
    }

    if (indexPath.section == 1) {
        static NSString *infoId = @"QDYTTInfo";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:infoId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:infoId];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
            cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        }
        if (indexPath.row == 0) {
            cell.textLabel.text = @"玻璃引擎";
            cell.detailTextLabel.text = QDYTTGlassEngineName();
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"底栏接管";
            cell.detailTextLabel.text = QDYTTGlassBarStatus();
        } else {
            cell.textLabel.text = @"系统支持";
            cell.detailTextLabel.text = QDYTTGlassNativeAvailable() ? @"iOS 26+ 原生玻璃" : @"旧系统 · 毛玻璃降级";
        }
        return cell;
    }

    static NSString *actId = @"QDYTTAction";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:actId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:actId];
        cell.textLabel.textColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
    }
    cell.textLabel.text = @"立即重绘底栏";
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2 && indexPath.row == 0) {
        QDYTTGlassRefresh();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          [self.tableView reloadData];
          [DYYYUtils showToast:[NSString stringWithFormat:@"YTT · %@", QDYTTGlassBarStatus()]];
        });
    }
}

- (void)qdSwitchChanged:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, "qd_ytt_key");
    if (!key) return;
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    QDYTTGlassRefresh();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self.tableView reloadData];
    });
}

@end
