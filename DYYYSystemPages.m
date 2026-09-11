#import "DYYYSystemPages.h"

#import "DYYYCompatibility.h"
#import "DYYYConstants.h"
#import "DYYYDiagnostics.h"
#import "DYYYHookManager.h"
#import "DYYYLogger.h"
#import "DYYYManager.h"
#import "DYYYSafetyGuard.h"
#import "DYYYSettingsHelper.h"
#import "DYYYSettingsIndex.h"
#import "DYYYTaskCenter.h"
#import "DYYYUtils.h"

#import <Photos/Photos.h>
#import <objc/runtime.h>

#pragma mark - 通用样式工具

// 自绘黑色线性图标（与设置行线稿风格一致，替代 emoji）
static UIImage *DYYYLineIconNamed(NSString *kind) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    UIImage *cached = cache[kind];
    if (cached) return cached;

    UIGraphicsImageRendererFormat *fmt = [[UIGraphicsImageRendererFormat alloc] init];
    fmt.scale = [UIScreen mainScreen].scale;
    fmt.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(18, 18) format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.blackColor setStroke];
        [UIColor.blackColor setFill];
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [p setLineWidth:1.7];

        if ([kind isEqualToString:@"gear"]) {              // 元抖核心
            [p appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(9, 9) radius:3.4 startAngle:0 endAngle:M_PI * 2 clockwise:YES]];
            [p stroke];
            for (int i = 0; i < 8; i++) {
                CGFloat a = i * M_PI / 4.0;
                [p removeAllPoints];
                [p moveToPoint:CGPointMake(9 + cosf(a) * 5.4, 9 + sinf(a) * 5.4)];
                [p addLineToPoint:CGPointMake(9 + cosf(a) * 7.6, 9 + sinf(a) * 7.6)];
                [p stroke];
            }
        } else if ([kind isEqualToString:@"shield"]) {     // Hook Safe Guard
            [p moveToPoint:CGPointMake(9, 1.8)];
            [p addLineToPoint:CGPointMake(15, 4)];
            [p addLineToPoint:CGPointMake(15, 8.6)];
            [p addCurveToPoint:CGPointMake(9, 16.2) controlPoint1:CGPointMake(15, 12.2) controlPoint2:CGPointMake(12.6, 15.1)];
            [p addCurveToPoint:CGPointMake(3, 8.6) controlPoint1:CGPointMake(5.4, 15.1) controlPoint2:CGPointMake(3, 12.2)];
            [p addLineToPoint:CGPointMake(3, 4)];
            [p closePath];
            [p stroke];
        } else if ([kind isEqualToString:@"cross"]) {      // 崩溃防护
            UIBezierPath *plus = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(6.6, 2.5, 4.8, 13) cornerRadius:1.6];
            [plus appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2.5, 6.6, 13, 4.8) cornerRadius:1.6]];
            [plus fill];
        } else if ([kind isEqualToString:@"box"]) {        // 任务中心
            [p moveToPoint:CGPointMake(9, 2.2)];
            [p addLineToPoint:CGPointMake(9, 10.6)];
            [p stroke];
            [p removeAllPoints];
            [p moveToPoint:CGPointMake(5.4, 7.6)];
            [p addLineToPoint:CGPointMake(9, 11.2)];
            [p addLineToPoint:CGPointMake(12.6, 7.6)];
            [p stroke];
            [p removeAllPoints];
            [p moveToPoint:CGPointMake(3, 12.4)];
            [p addLineToPoint:CGPointMake(3, 14.2)];
            [p addCurveToPoint:CGPointMake(4.8, 16) controlPoint1:CGPointMake(3, 15.2) controlPoint2:CGPointMake(3.8, 16)];
            [p addLineToPoint:CGPointMake(13.2, 16)];
            [p addCurveToPoint:CGPointMake(15, 14.2) controlPoint1:CGPointMake(14.2, 16) controlPoint2:CGPointMake(15, 15.2)];
            [p addLineToPoint:CGPointMake(15, 12.4)];
            [p stroke];
        } else if ([kind isEqualToString:@"magnifier"]) {  // 设置搜索索引
            [p appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(7.6, 7.6) radius:4.6 startAngle:0 endAngle:M_PI * 2 clockwise:YES]];
            [p stroke];
            [p removeAllPoints];
            [p moveToPoint:CGPointMake(10.9, 10.9)];
            [p addLineToPoint:CGPointMake(15.4, 15.4)];
            [p stroke];
        } else if ([kind isEqualToString:@"puzzle"]) {     // 依赖检查
            UIBezierPath *g = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2.8, 2.8, 5.6, 5.6) cornerRadius:1.4];
            [g appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(9.6, 2.8, 5.6, 5.6) cornerRadius:1.4]];
            [g appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2.8, 9.6, 5.6, 5.6) cornerRadius:1.4]];
            [g appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(9.6, 9.6, 5.6, 5.6) cornerRadius:1.4]];
            [g stroke];
        } else if ([kind isEqualToString:@"doc"]) {        // 诊断报告
            UIBezierPath *page = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3.5, 2, 9.5, 14) cornerRadius:2];
            page.lineCapStyle = kCGLineCapRound;
            [page setLineWidth:1.7];
            [page stroke];
            [p moveToPoint:CGPointMake(6, 6.4)];
            [p addLineToPoint:CGPointMake(10.5, 6.4)];
            [p stroke];
            [p removeAllPoints];
            [p moveToPoint:CGPointMake(6, 9.4)];
            [p addLineToPoint:CGPointMake(10.5, 9.4)];
            [p stroke];
            [p removeAllPoints];
            [p moveToPoint:CGPointMake(6, 12.4)];
            [p addLineToPoint:CGPointMake(9, 12.4)];
            [p stroke];
        } else if ([kind isEqualToString:@"exit"]) {       // 退出安全模式
            [p moveToPoint:CGPointMake(11, 2.6)];
            [p addLineToPoint:CGPointMake(4.6, 2.6)];
            [p addCurveToPoint:CGPointMake(3.4, 3.8) controlPoint1:CGPointMake(3.9, 2.6) controlPoint2:CGPointMake(3.4, 3.1)];
            [p addLineToPoint:CGPointMake(3.4, 14.2)];
            [p addCurveToPoint:CGPointMake(4.6, 15.4) controlPoint1:CGPointMake(3.4, 14.9) controlPoint2:CGPointMake(3.9, 15.4)];
            [p addLineToPoint:CGPointMake(11, 15.4)];
            [p stroke];
            [p removeAllPoints];
            [p moveToPoint:CGPointMake(8, 9)];
            [p addLineToPoint:CGPointMake(15.2, 9)];
            [p stroke];
            [p removeAllPoints];
            [p moveToPoint:CGPointMake(12.6, 6)];
            [p addLineToPoint:CGPointMake(15.4, 9)];
            [p addLineToPoint:CGPointMake(12.6, 12)];
            [p stroke];
        } else {
            return;
        }
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cache[kind] = img;
    return img;
}

static UIColor *DYYYPageBackgroundColor(void) {
    return [DYYYUtils isDarkMode] ? [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:1.0] : [UIColor colorWithRed:0.95 green:0.96 blue:0.97 alpha:1.0];
}

static UIColor *DYYYCardBackgroundColor(void) {
    return [DYYYUtils isDarkMode] ? [UIColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:1.0] : UIColor.whiteColor;
}

static NSString *DYYYTimeString(NSDate *date) {
    if (!date) {
        return @"";
    }
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      formatter = [[NSDateFormatter alloc] init];
      formatter.dateFormat = @"MM-dd HH:mm";
    });
    return [formatter stringFromDate:date];
}

static void DYYYShareFiles(UIViewController *host, NSArray<NSURL *> *fileURLs, NSString *fallbackText) {
    NSMutableArray *items = [NSMutableArray array];
    if (fileURLs.count > 0) {
        [items addObjectsFromArray:fileURLs];
    } else if (fallbackText) {
        [items addObject:fallbackText];
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = host.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(host.view.bounds.size.width / 2.0, host.view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    [host presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 状态中心

@interface DYYYStatusViewController ()
@property(nonatomic, strong) NSDictionary<NSString *, NSString *> *environmentInfoCache;
@end

@implementation DYYYStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"状态中心";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = DYYYPageBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    // 环境信息整页缓存一次，保证行数与取值顺序一致
    self.environmentInfoCache = [DYYYCompatibility environmentInfo];
}

- (NSArray<NSDictionary *> *)moduleRows {
    return @[
        @{ @"name" : @"元抖核心", @"icon" : @"gear", @"status" : @"正常运行" },
        @{ @"name" : @"Hook Safe Guard", @"icon" : @"shield", @"status" : [DYYYHookManager summaryText] },
        @{ @"name" : @"崩溃防护", @"icon" : @"cross", @"status" : [DYYYSafetyGuard isSafeMode] ? @"安全模式" : [NSString stringWithFormat:@"正常（计数 %lu）", (unsigned long)[DYYYSafetyGuard consecutiveCrashCount]] },
        @{ @"name" : @"任务中心", @"icon" : @"box", @"status" : [NSString stringWithFormat:@"运行中 %lu / 今日完成 %lu", (unsigned long)[[DYYYTaskCenter shared] activeTasks].count, (unsigned long)[[DYYYTaskCenter shared] finishedCountToday]] },
        @{ @"name" : @"设置搜索索引", @"icon" : @"magnifier", @"status" : [NSString stringWithFormat:@"%lu 项", (unsigned long)DYYYSettingsSearchIndex().count] },
        @{ @"name" : @"依赖检查", @"icon" : @"puzzle", @"status" : [DYYYCompatibility dependencyCheckPassed] ? @"全部通过" : @"存在缺失（部分功能不可用）" },
    ];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return self.environmentInfoCache.count;
        case 1: return self.moduleRows.count;
        case 2: return [DYYYSafetyGuard isSafeMode] ? 2 : 1;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"当前环境";
        case 1: return @"模块状态";
        case 2: return @"操作";
    }
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DYYYStatusCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    }
    cell.backgroundColor = DYYYCardBackgroundColor();
    cell.textLabel.textColor = [DYYYUtils isDarkMode] ? UIColor.whiteColor : [UIColor blackColor];
    cell.detailTextLabel.textColor = [DYYYUtils isDarkMode] ? [UIColor lightGrayColor] : [UIColor darkGrayColor];
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    switch (indexPath.section) {
        case 0: {
            NSString *key = self.environmentInfoCache.allKeys[indexPath.row];
            cell.textLabel.text = key;
            cell.detailTextLabel.text = self.environmentInfoCache[key];
            break;
        }
        case 1: {
            NSArray<NSDictionary *> *rows = self.moduleRows;
            NSDictionary *row = rows[indexPath.row];
            cell.textLabel.text = row[@"name"];
            cell.imageView.image = DYYYLineIconNamed(row[@"icon"]);
            cell.imageView.tintColor = cell.textLabel.textColor;
            cell.detailTextLabel.text = row[@"status"];
            break;
        }
        case 2: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"生成诊断报告";
                cell.imageView.image = DYYYLineIconNamed(@"doc");
                cell.detailTextLabel.text = @"";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = @"退出安全模式";
                cell.imageView.image = DYYYLineIconNamed(@"exit");
                cell.detailTextLabel.text = @"重启抖音后完整恢复";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            cell.imageView.tintColor = cell.textLabel.textColor;
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            NSString *report = [DYYYDiagnostics copyReportToPasteboard];
            [DYYYUtils showToast:@"诊断报告已复制到剪贴板"];
            DYYYShareFiles(self, @[], report);
            return;
        }
        if (indexPath.row == 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"退出安全模式" message:@"将清除连续崩溃计数并恢复全部功能，重启抖音后生效。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"确认退出" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
              [DYYYSafetyGuard exitSafeMode];
              self.environmentInfoCache = [DYYYCompatibility environmentInfo];
              [self.tableView reloadData];
              [DYYYUtils showToast:@"已退出安全模式，请重启抖音"];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

@end

#pragma mark - 运行日志

@interface DYYYLogViewController ()
@property(nonatomic, strong) NSArray<DYYYLogEntry *> *entries;
@property(nonatomic, assign) BOOL warningsOnly;
@end

@implementation DYYYLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"运行日志";
    self.view.backgroundColor = DYYYPageBackgroundColor();

    UIBarButtonItem *clearItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearTapped)];
    UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareTapped)];
    self.navigationItem.rightBarButtonItems = @[ shareItem, clearItem ];

    UISegmentedControl *segment = [[UISegmentedControl alloc] initWithItems:@[ @"全部", @"仅告警" ]];
    segment.selectedSegmentIndex = 0;
    [segment addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    segment.frame = CGRectMake(0, 0, 180, 30);
    self.navigationItem.titleView = segment;

    [self reloadEntries];
}

- (void)reloadEntries {
    self.entries = self.warningsOnly ? [DYYYLogger recentWarningsAndErrors] : [DYYYLogger recentLogs];
    [self.tableView reloadData];
}

- (void)segmentChanged:(UISegmentedControl *)segment {
    self.warningsOnly = (segment.selectedSegmentIndex == 1);
    [self reloadEntries];
}

- (void)clearTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空日志" message:@"将清除内存与磁盘日志。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
      [DYYYLogger clearLogs];
      [self reloadEntries];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareTapped {
    NSString *text = [DYYYLogger exportText];
    NSString *path = [DYYYUtils cachePathForFilename:@"元抖日志导出.txt"];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    DYYYShareFiles(self, @[[NSURL fileURLWithPath:path]], text);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DYYYLogCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.textLabel.numberOfLines = 3;
        cell.detailTextLabel.numberOfLines = 1;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    }
    cell.backgroundColor = DYYYCardBackgroundColor();

    DYYYLogEntry *entry = self.entries[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"[%@][%@] %@", entry.levelName, entry.module ?: @"", entry.message];
    cell.detailTextLabel.text = DYYYTimeString(entry.timestamp) ?: @"";

    switch (entry.level) {
        case DYYYLogLevelError:
        case DYYYLogLevelFatal:
            cell.textLabel.textColor = [UIColor systemRedColor];
            break;
        case DYYYLogLevelWarning:
            cell.textLabel.textColor = [UIColor systemOrangeColor];
            break;
        default:
            cell.textLabel.textColor = [DYYYUtils isDarkMode] ? UIColor.whiteColor : [UIColor blackColor];
            break;
    }
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

@end

#pragma mark - 任务中心

@implementation DYYYTaskCenterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"任务中心";
    self.view.backgroundColor = DYYYPageBackgroundColor();

    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:@"取消全部" style:UIBarButtonItemStylePlain target:self action:@selector(cancelAllTapped)];
    UIBarButtonItem *clearItem = [[UIBarButtonItem alloc] initWithTitle:@"清空历史" style:UIBarButtonItemStylePlain target:self action:@selector(clearHistoryTapped)];
    self.navigationItem.rightBarButtonItems = @[ clearItem, cancelItem ];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadData {
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)cancelAllTapped {
    [DYYYManager cancelAllDownloads];
    [DYYYUtils showToast:@"已请求取消全部下载任务"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self.tableView reloadData];
    });
}

- (void)clearHistoryTapped {
    [[DYYYTaskCenter shared] clearHistory];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"运行中" : @"历史记录";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 1 ? @"失败的下载会自动重试一次；点击失败记录可手动重新下载。" : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? MAX([[DYYYTaskCenter shared] activeTasks].count, 1) : [[DYYYTaskCenter shared] history].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DYYYTaskCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    cell.backgroundColor = DYYYCardBackgroundColor();
    cell.textLabel.textColor = [DYYYUtils isDarkMode] ? UIColor.whiteColor : [UIColor blackColor];
    cell.detailTextLabel.textColor = [DYYYUtils isDarkMode] ? [UIColor lightGrayColor] : [UIColor darkGrayColor];
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    if (indexPath.section == 0) {
        NSArray<DYYYTaskRecord *> *active = [[DYYYTaskCenter shared] activeTasks];
        if (active.count == 0) {
            cell.textLabel.text = @"暂无运行中的任务";
            cell.detailTextLabel.text = @"";
            cell.accessoryType = UITableViewCellAccessoryNone;
            return cell;
        }
        DYYYTaskRecord *record = active[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ [%@]", record.title, record.type ?: @"任务"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 已开始于 %@", DYYYTaskStateName(record.state), DYYYTimeString(record.createdAt)];
        UIProgressView *progress = (UIProgressView *)[cell viewWithTag:101];
        if (!progress) {
            progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
            progress.tag = 101;
            progress.frame = CGRectMake(cell.layoutMargins.left, 38, cell.contentView.frame.size.width - cell.layoutMargins.left - cell.layoutMargins.right, 4);
            progress.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:progress];
        }
        progress.hidden = NO;
        [progress setProgress:record.progress animated:NO];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    NSArray<DYYYTaskRecord *> *history = [[DYYYTaskCenter shared] history];
    if (indexPath.row >= (NSInteger)history.count) {
        cell.textLabel.text = @"";
        cell.detailTextLabel.text = @"";
        return cell;
    }
    DYYYTaskRecord *record = history[indexPath.row];
    NSString *icon;
    switch (record.state) {
        case DYYYTaskStateDone:      icon = @"√"; break;
        case DYYYTaskStateFailed:    icon = @"×"; break;
        case DYYYTaskStateCancelled: icon = @"○"; break;
        default:                     icon = @"…"; break;
    }
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@ [%@]", icon, record.title, record.type ?: @"任务"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", DYYYTaskStateName(record.state), DYYYTimeString(record.finishedAt ?: record.createdAt)];
    UIProgressView *progress = (UIProgressView *)[cell viewWithTag:101];
    progress.hidden = YES;
    cell.accessoryType = (record.state == DYYYTaskStateFailed && record.fileURL) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) {
        return;
    }
    NSArray<DYYYTaskRecord *> *history = [[DYYYTaskCenter shared] history];
    if (indexPath.row >= (NSInteger)history.count) {
        return;
    }
    DYYYTaskRecord *record = history[indexPath.row];
    if (record.state != DYYYTaskStateFailed || !record.fileURL) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重新下载" message:record.title preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重新下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
      NSURL *url = [NSURL URLWithString:record.fileURL];
      if (url) {
          [DYYYManager retryDownloadWithURL:url];
          [DYYYUtils showToast:@"已加入下载队列"];
      }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - 全局设置搜索

@interface DYYYSettingsSearchViewController ()
@property(nonatomic, strong) NSArray<NSDictionary<NSString *, id> *> *results;
@property(nonatomic, copy) NSString *query;
@end

@implementation DYYYSettingsSearchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置搜索";
    self.view.backgroundColor = DYYYPageBackgroundColor();

    UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    searchBar.placeholder = @"搜索功能，例如：下载 / 倍速 / 透明";
    searchBar.delegate = self;
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = searchBar;

    self.results = DYYYSettingsSearchIndex();
    [searchBar becomeFirstResponder];
}

- (void)applyQuery:(NSString *)text {
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    self.query = text;
    if (text.length == 0) {
        self.results = DYYYSettingsSearchIndex();
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"title CONTAINS[cd] %@ OR sub CONTAINS[cd] %@ OR id CONTAINS[cd] %@ OR cat CONTAINS[cd] %@", text, text, text, text];
        self.results = [DYYYSettingsSearchIndex() filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self applyQuery:searchText];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [self applyQuery:@""];
    [searchBar resignFirstResponder];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DYYYSearchCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    cell.backgroundColor = DYYYCardBackgroundColor();
    cell.textLabel.textColor = [DYYYUtils isDarkMode] ? UIColor.whiteColor : [UIColor blackColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.accessoryView = nil;

    NSDictionary<NSString *, id> *entry = self.results[indexPath.row];
    NSString *title = entry[@"title"];
    if (self.query.length > 0 && ![self.query isEqualToString:@""]) {
        NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title attributes:@{ NSFontAttributeName : [UIFont boldSystemFontOfSize:15], NSForegroundColorAttributeName : cell.textLabel.textColor }];
        NSRange range = [title rangeOfString:self.query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch];
        if (range.location != NSNotFound) {
            [attr addAttribute:NSForegroundColorAttributeName value:[UIColor systemBlueColor] range:range];
        }
        cell.textLabel.attributedText = attr;
    } else {
        cell.textLabel.text = title;
    }
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", entry[@"cat"], [entry[@"sub"] isKindOfClass:[NSString class]] && [entry[@"sub"] length] > 0 ? entry[@"sub"] : entry[@"id"]];

    // 开关类设置（cellType 37）直接在搜索页提供开关
    if ([entry[@"cell"] isKindOfClass:[NSNumber class]] && [entry[@"cell"] integerValue] == 37) {
        NSString *key = entry[@"id"];
        UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
        toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
        toggle.onTintColor = [UIColor systemBlueColor];
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        objc_setAssociatedObject(toggle, "dyyy_search_key", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.accessoryView = toggle;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, "dyyy_search_key");
    if (!key.length) {
        return;
    }
    BOOL enabled = sender.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [DYYYLogger info:@"SettingsSearch" message:[NSString stringWithFormat:@"通过搜索页切换 %@ = %@", key, enabled ? @"ON" : @"OFF"]];
    // 与设置页一致：应用依赖/互斥规则
    [DYYYSettingsHelper handleConflictsAndDependenciesForSetting:key isEnabled:enabled];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary<NSString *, id> *entry = self.results[indexPath.row];
    if ([entry[@"cell"] isKindOfClass:[NSNumber class]] && [entry[@"cell"] integerValue] == 37) {
        return; // 开关类直接在右侧切换
    }

    void (^jumpBlock)(void) = self.categoryBlocks[entry[@"cat"]];
    if (jumpBlock) {
        jumpBlock();
        NSString *category = entry[@"cat"];
        NSString *setting = entry[@"title"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          [DYYYUtils showToast:[NSString stringWithFormat:@"已进入「%@」，请查找「%@」", category, setting]];
        });
    } else {
        [DYYYUtils showToast:[NSString stringWithFormat:@"「%@」位于「%@」分类", entry[@"title"], entry[@"cat"]]];
    }
}

@end

#pragma mark - 配置快照

static NSString *DYYYSnapshotDirectory(void) {
    NSString *library = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [library stringByAppendingPathComponent:@"元抖/Snapshots"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSMutableDictionary<NSString *, id> *DYYYCollectCurrentSettings(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *allDefaults = [defaults dictionaryRepresentation];
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *key in allDefaults.allKeys) {
        if ([key hasPrefix:@"DYYY"]) {
            settings[key] = [defaults objectForKey:key];
        }
    }

    // 图标文件 Base64 一并打包（与备份格式兼容）
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dyyyFolderPath = [documentsPath stringByAppendingPathComponent:@"元抖"];
    NSArray<NSString *> *iconFileNames = @[ @"like_before.png", @"like_after.png", @"comment.png", @"unfavorite.png", @"favorite.png", @"share.png", @"tab_plus.png", @"qingping.gif" ];
    NSMutableDictionary *iconBase64Dict = [NSMutableDictionary dictionary];
    for (NSString *iconFileName in iconFileNames) {
        NSString *iconPath = [dyyyFolderPath stringByAppendingPathComponent:iconFileName];
        NSData *imageData = [NSData dataWithContentsOfFile:iconPath];
        if (imageData) {
            iconBase64Dict[iconFileName] = [imageData base64EncodedStringWithOptions:0];
        }
    }
    if (iconBase64Dict.count > 0) {
        settings[@"DYYYIconsBase64"] = iconBase64Dict;
    }
    return settings;
}

static BOOL DYYYApplySettingsSnapshot(NSDictionary *snapshot) {
    if (![snapshot isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    NSDictionary *iconBase64Dict = snapshot[@"DYYYIconsBase64"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *cleanSettings = [snapshot mutableCopy];

    if (iconBase64Dict && [iconBase64Dict isKindOfClass:[NSDictionary class]]) {
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *dyyyFolderPath = [documentsPath stringByAppendingPathComponent:@"元抖"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSString *iconFileName in iconBase64Dict) {
            NSString *base64String = iconBase64Dict[iconFileName];
            if (![base64String isKindOfClass:[NSString class]]) {
                continue;
            }
            NSData *imageData = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
            if (imageData) {
                [imageData writeToFile:[dyyyFolderPath stringByAppendingPathComponent:iconFileName] atomically:YES];
            }
        }
        [cleanSettings removeObjectForKey:@"DYYYIconsBase64"];
    }

    for (NSString *key in cleanSettings) {
        [defaults setObject:cleanSettings[key] forKey:key];
    }
    [defaults synchronize];
    return YES;
}

@implementation DYYYSnapshotViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"配置快照";
    self.view.backgroundColor = DYYYPageBackgroundColor();

    UIBarButtonItem *newItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(createSnapshotTapped)];
    self.navigationItem.rightBarButtonItem = newItem;
}

- (NSArray<NSURL *> *)snapshotFiles {
    NSString *dir = DYYYSnapshotDirectory();
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasSuffix:@".json"]) {
            [urls addObject:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]]];
        }
    }
    return [urls sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
      return [b.lastPathComponent compare:a.lastPathComponent];
    }];
}

- (void)createSnapshotTapped {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSMutableDictionary *settings = DYYYCollectCurrentSettings();
      // NSJSONSerialization 不支持 NSDate，必须用字符串时间戳
      static NSDateFormatter *metaFormatter;
      static dispatch_once_t metaFormatterToken;
      dispatch_once(&metaFormatterToken, ^{
        metaFormatter = [[NSDateFormatter alloc] init];
        metaFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
      });
      settings[@"DYYYSnapshotMeta"] = @{ @"pluginVersion" : DYYY_VERSION, @"createdAt" : [metaFormatter stringFromDate:[NSDate date]], @"featureCount" : @(settings.count) };

      NSError *jsonError = nil;
      NSData *jsonData = [NSJSONSerialization dataWithJSONObject:DYYYJSONSafeObject(settings) options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&jsonError];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (jsonError || !jsonData) {
            [DYYYUtils showToast:@"快照创建失败：无法序列化设置"];
            return;
        }
        static NSDateFormatter *formatter;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          formatter = [[NSDateFormatter alloc] init];
          formatter.dateFormat = @"yyyyMMdd-HHmmss";
        });
        NSString *fileName = [NSString stringWithFormat:@"Snapshot_%@_%lu项.json", [formatter stringFromDate:[NSDate date]], (unsigned long)(settings.count - 1)];
        BOOL ok = [jsonData writeToFile:[DYYYSnapshotDirectory() stringByAppendingPathComponent:fileName] atomically:YES];
        [DYYYUtils showToast:ok ? @"快照已创建" : @"快照写入失败"];
        [self.tableView reloadData];
      });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.snapshotFiles.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DYYYSnapshotCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    cell.backgroundColor = DYYYCardBackgroundColor();
    cell.textLabel.textColor = [DYYYUtils isDarkMode] ? UIColor.whiteColor : [UIColor blackColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    NSArray<NSURL *> *files = self.snapshotFiles;
    if (files.count == 0) {
        cell.textLabel.text = @"暂无快照，点击右上角 + 创建";
        cell.detailTextLabel.text = @"";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    NSURL *fileURL = files[indexPath.row];
    cell.textLabel.text = fileURL.lastPathComponent;
    NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:fileURL] options:0 error:nil][@"DYYYSnapshotMeta"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 项设置 · 插件 v%@", meta[@"featureCount"] ?: @"?", meta[@"pluginVersion"] ?: @"?"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<NSURL *> *files = self.snapshotFiles;
    if (indexPath.row >= (NSInteger)files.count) {
        return;
    }
    NSURL *fileURL = files[indexPath.row];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:fileURL.lastPathComponent message:@"选择要执行的操作" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复此快照" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *snapshot = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:fileURL] options:0 error:nil];
        BOOL ok = DYYYApplySettingsSnapshot(snapshot);
        dispatch_async(dispatch_get_main_queue(), ^{
          [DYYYUtils showToast:ok ? @"快照已恢复，重启抖音生效" : @"快照文件格式错误"];
        });
      });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"分享 / 导出" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
      DYYYShareFiles(self, @[ fileURL ], nil);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
      [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
      [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    }
    [self presentViewController:alert animated:YES completion:nil];
}

@end
