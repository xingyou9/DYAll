// DYYDCenterPages.m — DYAll 5.0.2 中心页实现
//
// 四个中心页全部改走 AWESettingBaseViewController 容器（与「系统与性能」老页面同一条路）：
//   · 页面由抖音自己的设置机制渲染 → 白底、导航栏、返回手势与老界面完全一致；
//   · 裸 UITableViewController 在抖音自定义导航容器里会转场冻结 + 前一页透出（5.0/5.0.1 的「透明框」bug 根源）；
//   · 开关类条目直接复用 createSettingItem（cellType 37 自动绑定 NSUserDefaults 键）。
//
// 性能指标为进入页面时的快照（抖音容器没有安全的逐行刷新通道），重进页面即刷新。
#import "DYYDCenterPages.h"

#import "AwemeHeaders.h"
#import "DYYYSettingsHelper.h"
#import "DYYYCacheManager.h"
#import "DYYYModeManager.h"
#import "DYYYPerfMonitor.h"
#import "DYYYUtils.h"

#pragma mark - 通用

static NSString *DYYDFormatBytes(unsigned long long bytes) {
    if (bytes >= 1024ULL * 1024ULL) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    if (bytes >= 1024ULL) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%llu B", bytes];
}

static AWESettingItemModel *DYYDInfoRow(NSString *identifier, NSString *title, NSString *detail) {
    AWESettingItemModel *item = [[NSClassFromString(@"AWESettingItemModel") alloc] init];
    item.identifier = identifier;
    item.title = title;
    item.detail = detail;
    item.type = 0;
    item.cellType = 26;
    item.colorStyle = 0;
    item.isEnable = NO;   // 只读行
    return item;
}

static AWESettingItemModel *DYYDActionRow(NSString *identifier, NSString *title, NSString *detail, void (^action)(void)) {
    AWESettingItemModel *item = [[NSClassFromString(@"AWESettingItemModel") alloc] init];
    item.identifier = identifier;
    item.title = title;
    item.detail = detail;
    item.type = 0;
    item.cellType = 26;
    item.colorStyle = 0;
    item.isEnable = YES;
    item.cellTappedBlock = action;
    return item;
}

static AWESettingItemModel *DYYDSwitchRow(NSString *key, NSString *title, NSString *subtitle) {
    return [DYYYSettingsHelper createSettingItem:@{
        @"identifier" : key,
        @"title" : title,
        @"subTitle" : subtitle,
        @"detail" : @"",
        @"cellType" : @37
    } cellTapHandlers:nil];
}

static AWESettingSectionModel *DYYDSection(NSString *title, NSString *footer, NSArray *items) {
    // 与老页面同款官方 helper（内部处理 header 高度与 footer 字段）
    return [DYYYSettingsHelper createSectionWithTitle:title footerTitle:footer items:items];
}

#pragma mark - 主类

@implementation DYYDCenterPages
@end

#pragma mark - 模式中心

@implementation DYYDCenterPages (Mode)

+ (UIViewController *)modeCenterPage {
    DYYYModeManager *mm = [DYYYModeManager shared];
    NSString *current = [mm currentModeID];

    NSMutableArray<AWESettingItemModel *> *items = [NSMutableArray array];
    for (NSDictionary *m in [mm allModes]) {
        NSString *mid = m[@"id"];
        BOOL isCurrent = [mid isEqualToString:current];
        NSString *name = m[@"name"];
        NSString *detail = isCurrent ? @"当前使用" : @"";
        AWESettingItemModel *row = DYYDActionRow([@"mode." stringByAppendingString:mid],
                                                 name, detail, ^{
            NSUInteger applied = [[DYYYModeManager shared] applyMode:mid];
            if ([mid isEqualToString:@"custom"]) {
                [DYYYUtils showToast:@"已切换到自定义模式"];
            } else {
                [DYYYUtils showToast:[NSString stringWithFormat:@"%@已应用（%lu 项开关）", name, (unsigned long)applied]];
            }
        });
        [items addObject:row];
    }

    AWESettingSectionModel *section = DYYDSection(@"选择一个模式，批量应用配套开关",
                                                  @"切换模式会自动处理功能依赖与冲突；自定义模式不改动任何开关。重进本页可查看当前模式。",
                                                  items);
    return [DYYYSettingsHelper createSubSettingsViewController:@"模式中心" sections:@[ section ]];
}

@end

#pragma mark - 性能中心

@implementation DYYDCenterPages (Perf)

+ (UIViewController *)perfCenterPage {
    DYYYPerfMonitor *mon = [DYYYPerfMonitor shared];
    double used = [mon memoryUsedMB];
    double free = [mon memoryAvailableMB];
    double fps = [mon latestFPS];
    double cpu = [mon cpuUsagePercent];

    NSArray *metricRows = @[
        DYYDInfoRow(@"perf.mem", @"内存占用", used >= 0 ? [NSString stringWithFormat:@"%.1f MB", used] : @"不可用"),
        DYYDInfoRow(@"perf.free", @"可用内存", free >= 0 ? [NSString stringWithFormat:@"%.1f MB", free] : @"不可用"),
        DYYDInfoRow(@"perf.fps", @"帧率", fps > 1 ? [NSString stringWithFormat:@"%.0f FPS", fps] : @"采样中…"),
        DYYDInfoRow(@"perf.cpu", @"CPU 占用", cpu >= 0 ? [NSString stringWithFormat:@"%.1f %%", cpu] : @"不可用"),
    ];

    AWESettingItemModel *optRow = DYYDSwitchRow(@"DYYY.AutoOptimize", @"自动优化",
                                                @"检测到内存压力时自动：清理临时缓存、降低玻璃特效 60 秒、暂停变色采样");
    // createSettingItem 默认把 detail 置为已存值；开关行不该有 detail
    optRow.detail = @"";

    AWESettingItemModel *runRow = DYYDActionRow(@"perf.run", @"立即优化", @"清理临时缓存并降级特效 60 秒", ^{
        [[DYYYPerfMonitor shared] performOptimizationNow];
        [DYYYUtils showToast:@"已执行优化：缓存已清理，特效临时降级 60 秒"];
    });

    AWESettingSectionModel *s0 = DYYDSection(@"实时指标", @"进入本页时的快照，退出重进即可刷新。", metricRows);
    AWESettingSectionModel *s1 = DYYDSection(@"自动优化", nil, @[ optRow ]);
    AWESettingSectionModel *s2 = DYYDSection(@"操作", nil, @[ runRow ]);
    return [DYYYSettingsHelper createSubSettingsViewController:@"性能中心" sections:@[ s0, s1, s2 ]];
}

@end

#pragma mark - 缓存中心

@implementation DYYDCenterPages (Cache)

+ (UIViewController *)cacheCenterPage {
    DYYYCacheManager *cm = [DYYYCacheManager shared];
    NSArray<DYYYCacheItem *> *cacheItems = [cm allItems];

    NSMutableArray<AWESettingItemModel *> *items = [NSMutableArray array];
    for (DYYYCacheItem *ci in cacheItems) {
        NSString *itemID = ci.itemID;
        NSString *name = ci.name;
        AWESettingItemModel *row = DYYDActionRow([@"cache." stringByAppendingString:itemID],
                                                 name, DYYDFormatBytes(ci.bytes), ^{
            unsigned long long freed = [[DYYYCacheManager shared] clearItem:itemID];
            [DYYYUtils showToast:[NSString stringWithFormat:@"已清理 %@", DYYDFormatBytes(freed)]];
        });
        [items addObject:row];
    }

    AWESettingItemModel *cleanAll = DYYDActionRow(@"cache.all", @"全部清理（保留配置与备份）", @"", ^{
        unsigned long long freed = [[DYYYCacheManager shared] clearAll];
        [DYYYUtils showToast:[NSString stringWithFormat:@"已清理 %@", DYYDFormatBytes(freed)]];
    });
    cleanAll.colorStyle = 2;   // 危险色，与「清除设置」风格一致
    [items addObject:cleanAll];

    NSString *footer = [NSString stringWithFormat:@"总大小 %@。超过上限（500 MB）时启动自动清理临时文件。清理后重进本页刷新大小。",
                        DYYDFormatBytes([cm totalBytes])];
    AWESettingSectionModel *section = DYYDSection(@"缓存分类（真实大小）", footer, items);
    return [DYYYSettingsHelper createSubSettingsViewController:@"缓存管理" sections:@[ section ]];
}

@end

#pragma mark - 隐私中心

@implementation DYYDCenterPages (Privacy)

+ (UIViewController *)privacyCenterPage {
    AWESettingItemModel *principle = DYYDInfoRow(@"privacy.principle", @"最小化收集 · 默认关闭非必要数据", @"");
    AWESettingItemModel *verbose = DYYDSwitchRow(@"DYYYEnableVerboseLog", @"详细日志", @"仅保存在本机，可随时清理");
    AWESettingItemModel *island = DYYDSwitchRow(@"DYYYBlockDynamicIsland", @"屏蔽灵动岛弹出", @"拦截抖音的灵动岛实时活动展开");
    verbose.detail = @"";
    island.detail = @"";

    AWESettingItemModel *wipe = DYYDActionRow(@"privacy.wipe", @"清除全部本地数据（临时文件 + 日志）", @"", ^{
        unsigned long long freed = [[DYYYCacheManager shared] clearAll];
        [DYYYUtils showToast:[NSString stringWithFormat:@"已清除 %@", DYYDFormatBytes(freed)]];
    });
    wipe.colorStyle = 2;

    AWESettingSectionModel *s0 = DYYDSection(@"数据原则",
                                             @"DYAll 不上传任何数据：无账号体系、无埋点、无远程上报。日志、配置、下载记录全部仅保存在本机，可随时清理。",
                                             @[ principle ]);
    AWESettingSectionModel *s1 = DYYDSection(@"本地行为开关", nil, @[ verbose, island ]);
    AWESettingSectionModel *s2 = DYYDSection(@"数据清理", @"配置与备份保留，不会被清除。", @[ wipe ]);
    return [DYYYSettingsHelper createSubSettingsViewController:@"隐私中心" sections:@[ s0, s1, s2 ]];
}

@end
