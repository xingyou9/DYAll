/**
 * YTT 功能页 — 元抖设置内嵌的液态玻璃适配面板
 *
 * 完整呈现 YTT v2.0 的全部功能：
 *  - 玻璃模式状态（原生 UIGlassEffect / 降级）
 *  - 4 个功能开关，直接读写 YTT 的偏好键（与 YTT 自带面板完全互通）
 *  - 附加增强说明与入口说明
 *  - 玻璃风格头部，与元抖设置页视觉统一
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface QDYTTPageController : UITableViewController
@end

@implementation QDYTTPageController

typedef struct { NSString *title; NSString *desc; NSString *key; } QDYTTFeature;

static NSArray *_QDYTTFeatures(void) {
    static NSArray *a; static dispatch_once_t once;
    dispatch_once(&once, ^{
        a = @[
            @[@"液态玻璃",        @"把底栏模糊层换成官方玻璃",           @"YTT.glass"],
            @[@"清除底栏渐变",    @"摘掉压暗玻璃的黑色渐变",             @"YTT.clear"],
            @[@"背景延伸",        @"作品背景铺满屏幕底部",               @"YTT.extend"],
            @[@"玻璃胶囊跟随",    @"切换时玻璃胶囊跟随滑动",             @"YTT.capsule"],
        ];
    });
    return a;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"YTT";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    if (self.navigationController) {
        self.navigationController.navigationBar.tintColor =
            [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1];
    }

    // 头部：渐变卡（与元抖设置页 Hero 风格统一）
    CGFloat w = self.tableView.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 96)];
    header.backgroundColor = [UIColor clearColor];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 8, w - 32, 80)];
    card.layer.cornerRadius = 20;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:card];

    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.colors = @[(id)[UIColor colorWithRed:0.10 green:0.55 blue:0.62 alpha:1].CGColor,
                    (id)[UIColor colorWithRed:0.22 green:0.35 blue:0.85 alpha:1].CGColor];
    grad.startPoint = CGPointMake(0, 0);
    grad.endPoint = CGPointMake(1, 1);
    grad.frame = CGRectMake(0, 0, w - 32, 80);
    [card.layer insertSublayer:grad atIndex:0];

    UILabel *t = [[UILabel alloc] init];
    t.text = @"YTT · 液态玻璃适配";
    t.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    t.textColor = UIColor.whiteColor;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:t];

    BOOL native = (NSClassFromString(@"UIGlassEffect") != nil);
    UILabel *s = [[UILabel alloc] init];
    s.text = native ? @"玻璃:原生" : @"玻璃:降级";
    s.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    s.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:s];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
        [t.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [t.centerYAnchor constraintEqualToAnchor:card.centerYAnchor constant:-11],
        [s.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],
        [s.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:4],
    ]];
    self.tableView.tableHeaderView = header;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"功能开关" : (section == 1 ? @"附加增强" : @"入口");
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 4 : (section == 1 ? 3 : 2);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *swId = @"QDYTTSw", *infoId = @"QDYTTInfo";
    if (ip.section == 0) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:swId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:swId];
            UISwitch *sw = [[UISwitch alloc] init];
            [sw addTarget:self action:@selector(qdSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        NSArray *f = _QDYTTFeatures()[ip.row];
        cell.textLabel.text = f[0];
        cell.detailTextLabel.text = f[1];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        UISwitch *sw = (UISwitch *)cell.accessoryView;
        sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:f[2]];
        objc_setAssociatedObject(sw, "yttkey", f[2], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return cell;
    }

    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:infoId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:infoId];
    if (ip.section == 1) {
        cell.textLabel.text = @[@"消除色差", @"滑动指示器", @"作品图层"][ip.row];
        cell.detailTextLabel.text = @"随液态玻璃开关生效";
    } else {
        cell.textLabel.text = @[@"右上角 YTT 悬浮按钮", @"长按页面 或 双指双击"][ip.row];
        cell.detailTextLabel.text = @"调出 YTT 面板";
    }
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)qdSwitchChanged:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, "yttkey");
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:key];
}

@end
