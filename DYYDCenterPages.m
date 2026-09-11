// DYYDCenterPages.m — DYAll 5.0 中心页实现（真实数据 + 设计系统令牌）
#import "DYYDCenterPages.h"
#import "DYYDDesign.h"
#import "DYYYPerfMonitor.h"
#import "DYYYCacheManager.h"
#import "DYYYConfigManager.h"
#import "DYYYModeManager.h"
#import "DYYYUtils.h"

#pragma mark - 通用

// 与 DYYYSystemPages 的老页面同款：页面必须不透明。
// 之前 tableView 背景是 clearColor，push 进抖音导航栈后透出下面的设置页，
// 表现为「两个页面叠在一起」的渲染错乱。
static UIColor *DYYDPageBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:1]
            : [UIColor colorWithRed:0.95 green:0.96 blue:0.97 alpha:1];
    }];
}

static UIColor *DYYDCellBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:1]
            : UIColor.whiteColor;
    }];
}

static NSString *DYYDFormatBytes(unsigned long long bytes) {
    if (bytes >= 1024ULL * 1024ULL) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    if (bytes >= 1024ULL) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%llu B", bytes];
}

static UITableViewCell *DYYDDequeue(UITableView *tv) {
    static NSString *ident = @"DYYDCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:ident];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ident];
    cell.textLabel.font = DYYDFontBody();
    cell.detailTextLabel.font = DYYDFontMetric();
    cell.backgroundColor = DYYDCellBackgroundColor();
    return cell;
}

static void DYYDConfirm(UIViewController *vc, NSString *title, NSString *message, void (^onOK)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { onOK(); }]];
    [vc presentViewController:alert animated:DYYDMotionAllowed() completion:nil];
}

static void DYYDToast(NSString *msg) {
    [DYYYUtils showToast:msg];
}

#pragma mark - 模式中心

@implementation DYYYModeCenterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"模式中心";
    self.tableView.separatorColor = DYYDColorSeparator();
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[DYYYModeManager shared] allModes].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"选择一个模式，批量应用配套开关";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"切换模式会自动处理功能依赖与冲突；自定义模式不改动任何开关。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = DYYDDequeue(tableView);
    NSDictionary *m = [[DYYYModeManager shared] allModes][indexPath.row];
    cell.textLabel.text = m[@"name"];
    cell.detailTextLabel.text = m[@"subtitle"];
    cell.detailTextLabel.font = DYYDFontCaption();
    if ([m[@"id"] isEqualToString:[[DYYYModeManager shared] currentModeID]]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.textLabel.textColor = DYYDColorPrimary();
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textColor = DYYDColorLabel();
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:DYYDMotionAllowed()];
    NSDictionary *m = [[DYYYModeManager shared] allModes][indexPath.row];
    NSUInteger applied = [[DYYYModeManager shared] applyMode:m[@"id"]];
    if ([m[@"id"] isEqualToString:@"custom"]) {
        DYYDToast(@"已切换到自定义模式");
    } else {
        DYYDToast([NSString stringWithFormat:@"%@已应用（%lu 项开关）", m[@"name"], (unsigned long)applied]);
    }
    [tableView reloadData];
}

@end

#pragma mark - 性能中心

@interface DYYYPerfCenterViewController ()
@property (nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation DYYYPerfCenterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"性能中心";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = DYYDPageBackgroundColor();
    self.tableView.separatorColor = DYYDColorSeparator();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDataSafe) name:DYYYPerfOptimizeNotification object:nil];
}

- (void)reloadDataSafe {
    if ([NSThread isMainThread]) [self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[DYYYPerfMonitor shared] startFPSsampling];
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    NSTimer *t = [NSTimer timerWithTimeInterval:2.0 target:self selector:@selector(refreshMetrics) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    self.refreshTimer = t;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    [[DYYYPerfMonitor shared] stopFPSsampling];
}

- (void)dealloc {
    [_refreshTimer invalidate];
    _refreshTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refreshMetrics {
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 4;
    if (section == 1) return 1;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"实时指标（每 2 秒刷新）";
    if (section == 1) return @"自动优化";
    return @"操作";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"检测到内存压力时自动：清理临时缓存、降低玻璃特效 60 秒、暂停变色采样。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = DYYDDequeue(tableView);
    DYYYPerfMonitor *mon = [DYYYPerfMonitor shared];
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0: {
                double used = [mon memoryUsedMB];
                cell.textLabel.text = @"内存占用";
                cell.detailTextLabel.text = used >= 0 ? [NSString stringWithFormat:@"%.1f MB", used] : @"不可用";
                cell.detailTextLabel.textColor = used > 1400 ? DYYDColorWarning() : DYYDColorSuccess();
                break;
            }
            case 1: {
                double free = [mon memoryAvailableMB];
                cell.textLabel.text = @"可用内存";
                cell.detailTextLabel.text = free >= 0 ? [NSString stringWithFormat:@"%.1f MB", free] : @"不可用";
                cell.detailTextLabel.textColor = DYYDColorSecondaryLabel();
                break;
            }
            case 2: {
                double fps = [mon latestFPS];
                cell.textLabel.text = @"帧率";
                cell.detailTextLabel.text = fps > 1 ? [NSString stringWithFormat:@"%.0f FPS", fps] : @"采样中…";
                cell.detailTextLabel.textColor = (fps > 1 && fps < 45) ? DYYDColorWarning() : DYYDColorSuccess();
                break;
            }
            case 3: {
                double cpu = [mon cpuUsagePercent];
                cell.textLabel.text = @"CPU 占用";
                cell.detailTextLabel.text = cpu >= 0 ? [NSString stringWithFormat:@"%.1f %%", cpu] : @"不可用";
                cell.detailTextLabel.textColor = cpu > 60 ? DYYDColorWarning() : DYYDColorSuccess();
                break;
            }
        }
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @"自动优化";
        cell.detailTextLabel.text = nil;
        UISwitch *sw = [[UISwitch alloc] init];
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        sw.on = [defs objectForKey:@"DYYY.AutoOptimize"] == nil ? YES : [defs boolForKey:@"DYYY.AutoOptimize"];
        [sw addTarget:self action:@selector(autoOptToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.textLabel.text = @"立即优化";
        cell.textLabel.textColor = DYYDColorPrimary();
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)autoOptToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"DYYY.AutoOptimize"];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:DYYDMotionAllowed()];
    if (indexPath.section == 2) {
        [[DYYYPerfMonitor shared] performOptimizationNow];
        DYYDToast(@"已执行优化：缓存已清理，特效临时降级 60 秒");
    }
}

@end

#pragma mark - 缓存中心

@implementation DYYYCacheCenterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"缓存管理";
    self.tableView.separatorColor = DYYDColorSeparator();
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[DYYYCacheManager shared] autoCleanIfOverLimit];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[DYYYCacheManager shared] allItems].count + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"缓存分类（真实大小）";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"总大小 %@。超过上限（500 MB）时启动自动清理临时文件。", DYYDFormatBytes([[DYYYCacheManager shared] totalBytes])];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = DYYDDequeue(tableView);
    NSArray<DYYYCacheItem *> *items = [[DYYYCacheManager shared] allItems];
    if (indexPath.row < (NSInteger)items.count) {
        DYYYCacheItem *item = items[indexPath.row];
        cell.textLabel.text = item.name;
        cell.detailTextLabel.text = DYYDFormatBytes(item.bytes);
        cell.detailTextLabel.textColor = DYYDColorSecondaryLabel();
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"全部清理（保留配置与备份）";
        cell.textLabel.textColor = DYYDColorError();
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:DYYDMotionAllowed()];
    NSArray<DYYYCacheItem *> *items = [[DYYYCacheManager shared] allItems];
    if (indexPath.row < (NSInteger)items.count) {
        DYYYCacheItem *item = items[indexPath.row];
        if ([item.itemID isEqualToString:@"config"]) {
            DYYDConfirm(self, @"清理配置文件", @"将删除配置备份与导出文件（不影响当前生效的设置）。", ^{
                [[DYYYCacheManager shared] clearItem:item.itemID];
                DYYDToast(@"配置文件已清理");
                [tableView reloadData];
            });
            return;
        }
        unsigned long long freed = [[DYYYCacheManager shared] clearItem:item.itemID];
        DYYDToast([NSString stringWithFormat:@"已清理 %@", DYYDFormatBytes(freed)]);
        [tableView reloadData];
    } else {
        DYYDConfirm(self, @"全部清理", @"将删除临时下载文件与运行日志（保留配置与备份）。", ^{
            unsigned long long freed = [[DYYYCacheManager shared] clearAll];
            DYYDToast([NSString stringWithFormat:@"已清理 %@", DYYDFormatBytes(freed)]);
            [tableView reloadData];
        });
    }
}

@end

#pragma mark - 隐私中心

@implementation DYYYPrivacyCenterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"隐私中心";
    self.tableView.separatorColor = DYYDColorSeparator();
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 2;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"数据原则";
    if (section == 1) return @"本地行为开关";
    return @"数据清理";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"DYAll 不上传任何数据：无账号体系、无埋点、无远程上报。日志、配置、下载记录全部仅保存在本机，可随时清理。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = DYYDDequeue(tableView);
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if (indexPath.section == 0) {
        cell.textLabel.text = @"最小化收集 · 默认关闭非必要数据";
        cell.textLabel.font = DYYDFontCaption();
        cell.textLabel.textColor = DYYDColorSecondaryLabel();
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1) {
        UISwitch *sw = [[UISwitch alloc] init];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"详细日志";
            cell.detailTextLabel.text = nil;
            sw.on = [defs boolForKey:@"DYYYEnableVerboseLog"];
            [sw addTarget:self action:@selector(verboseToggled:) forControlEvents:UIControlEventValueChanged];
        } else {
            cell.textLabel.text = @"屏蔽灵动岛弹出";
            cell.detailTextLabel.text = nil;
            sw.on = [defs boolForKey:@"DYYYBlockDynamicIsland"];
            [sw addTarget:self action:@selector(islandToggled:) forControlEvents:UIControlEventValueChanged];
        }
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.textLabel.text = @"清除全部本地数据（临时文件 + 日志）";
        cell.textLabel.textColor = DYYDColorError();
        cell.detailTextLabel.text = nil;
    }
    return cell;
}

- (void)verboseToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"DYYYEnableVerboseLog"];
    DYYDToast(sw.on ? @"详细日志已开启（仅本机保存）" : @"详细日志已关闭");
}

- (void)islandToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"DYYYBlockDynamicIsland"];
    DYYDToast(sw.on ? @"灵动岛弹出已屏蔽" : @"灵动岛弹出已恢复");
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:DYYDMotionAllowed()];
    if (indexPath.section == 2) {
        DYYDConfirm(self, @"清除本地数据", @"将删除临时下载文件与全部运行日志。配置与备份保留。", ^{
            unsigned long long freed = [[DYYYCacheManager shared] clearAll];
            DYYDToast([NSString stringWithFormat:@"已清除 %@", DYYDFormatBytes(freed)]);
        });
    }
}

@end
