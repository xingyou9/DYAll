//
//  QDExtra.xm
//  元抖 — 系统增强
//
//  三组能力，全部走「偏好开关 + 运行时兜底」，任何一项缺少目标类/方法时自动失效，
//  不会影响抖音主流程：
//
//  A. 灵动岛 / 实时活动屏蔽
//     抖音播放视频时会持续更新 MPNowPlayingInfoCenter，iOS 16.1+ 会把「正在播放」
//     顶到灵动岛上，刷视频时反复弹出。这里掐掉信息更新并撤销远程控制注册。
//
//  B. 性能与流畅度
//     - 收紧 NSURLCache 内存上限，缓解内存压力
//     - 压低视频预加载数量（动态探测，探测不到静默跳过）
//     - 可选关掉大面积毛玻璃（离屏渲染大户）
//
//  C. 交互防护
//     - 屏蔽摇一摇广告跳转
//     - 屏蔽录屏 / 截屏检测
//     - 屏蔽青少年模式弹窗
//     - 可选关闭触感反馈
//

#import "QDExtra.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>

#import "DYYYSettingsHelper.h"
#import "DYYYUtils.h"

#pragma mark - 偏好键

static NSString *const kQDBlockIsland   = @"DYYYBlockDynamicIsland";
static NSString *const kQDTurboCache    = @"DYYYPerfLowMemory";
static NSString *const kQDReducePreload = @"DYYYPerfReducePreload";
static NSString *const kQDDisableBlur   = @"DYYYPerfDisableBlur";
static NSString *const kQDBlockShake    = @"DYYYBlockShakeAd";
static NSString *const kQDBlockCapture  = @"DYYYBlockCaptureDetection";
static NSString *const kQDBlockTeen     = @"DYYYBlockTeenModeAlert";
static NSString *const kQDDisableHaptic = @"DYYYDisableHaptic";

// 元抖自己的玻璃视图打这个 tag，避免被「关闭毛玻璃」误伤
#define QD_KEEP_GLASS_TAG 993344

static BOOL QDBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

static void QDExtraRegisterDefaults(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            kQDBlockIsland   : @YES, // 用户明确要求：灵动岛不许再弹
            kQDTurboCache    : @YES,
            kQDReducePreload : @YES,
            kQDDisableBlur   : @NO,  // 会改观感，默认关
            kQDBlockShake    : @YES,
            kQDBlockCapture  : @YES,
            kQDBlockTeen     : @YES,
            kQDDisableHaptic : @NO,
        }];
    });
}

#pragma mark - 动态方法替换（找不到就完全不动）

typedef long long (*QDNumericIMP)(id, SEL);

static NSUInteger QDHookNumericGetters(NSArray<NSString *> *classNames, NSArray<NSString *> *selNames, long long value) {
    NSUInteger hits = 0;
    for (NSString *cn in classNames) {
        Class cls = NSClassFromString(cn);
        if (!cls) continue;
        for (NSString *sn in selNames) {
            SEL sel = NSSelectorFromString(sn);
            Method m = class_getInstanceMethod(cls, sel);
            if (!m) continue;
            const char *enc = method_getTypeEncoding(m);
            if (!enc) continue;
            // 只动确定是整数返回值的方法，绝不碰返回对象的
            if (enc[0] != 'q' && enc[0] != 'Q' && enc[0] != 'i' && enc[0] != 'I' &&
                enc[0] != 'l' && enc[0] != 'L' && enc[0] != 's' && enc[0] != 'S') {
                continue;
            }
            if (objc_getAssociatedObject(cls, sel)) continue; // 已经换过
            IMP orig = method_getImplementation(m);
            if (!orig) continue;
            QDNumericIMP origTyped = (QDNumericIMP)orig;
            long long forced = value;
            IMP stub = imp_implementationWithBlock(^long long(__unsafe_unretained id selfObj) {
                if (!QDBool(kQDReducePreload)) {
                    return origTyped(selfObj, sel);
                }
                return forced;
            });
            if (!stub) continue;
            class_replaceMethod(cls, sel, stub, enc);
            objc_setAssociatedObject(cls, sel, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            hits++;
        }
    }
    return hits;
}

static void QDApplyPreloadPolicy(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *classes = @[ @"AWEFeedPreloadManager", @"AWEAwemePreloadManager",
                              @"AWEVideoPreloadManager", @"AWEFeedPreloadConfig",
                              @"AWEPreloadConfig", @"AWEFeedCacheConfig" ];
        NSArray *sels = @[ @"preloadCount", @"maxPreloadCount", @"preloadSize",
                           @"preloadNum", @"preloadNumber", @"cacheCount",
                           @"maxCacheCount", @"preloadDuration" ];
        QDHookNumericGetters(classes, sels, 1);
    });
}

static void QDApplyCachePolicy(void) {
    if (!QDBool(kQDTurboCache)) return;
    NSURLCache *cache = [NSURLCache sharedURLCache];
    if (cache.memoryCapacity > 96 * 1024 * 1024) {
        cache.memoryCapacity = 96 * 1024 * 1024;
    }
    if (cache.diskCapacity > 512 * 1024 * 1024) {
        cache.diskCapacity = 512 * 1024 * 1024;
    }
}

#pragma mark - 撤销远程控制注册

static void QDDisableRemoteCommands(void) {
    if (!QDBool(kQDBlockIsland)) return;
    MPRemoteCommandCenter *center = [MPRemoteCommandCenter sharedCommandCenter];
    if (!center) return;
    NSArray *keyPaths = @[ @"playCommand", @"pauseCommand", @"togglePlayPauseCommand",
                           @"nextTrackCommand", @"previousTrackCommand",
                           @"changePlaybackPositionCommand" ];
    for (NSString *kp in keyPaths) {
        @try {
            MPRemoteCommand *cmd = [center valueForKey:kp];
            if (![cmd isKindOfClass:[MPRemoteCommand class]]) continue;
            cmd.enabled = NO;
        } @catch (__unused NSException *e) {
        }
    }
}

#pragma mark - A. 灵动岛 / 正在播放

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    if (QDBool(kQDBlockIsland)) {
        %orig(nil);
        return;
    }
    %orig;
}

%end

#pragma mark - B. 可选：关掉大面积毛玻璃

%hook UIVisualEffectView

- (void)didMoveToWindow {
    %orig;
    if (!QDBool(kQDDisableBlur)) return;
    if (self.tag == QD_KEEP_GLASS_TAG) return;          // 元抖自己的玻璃不关
    if (self.window == nil) return;
    if (self.bounds.size.height <= 140) return;          // 只关大屏整块的
    NSString *cn = NSStringFromClass([self class]);
    if (![cn hasPrefix:@"AWE"] && ![cn hasPrefix:@"IES"] && ![cn hasPrefix:@"HTS"]) return;
    self.hidden = YES;
}

%end

#pragma mark - C. 交互防护

%hook UIViewController

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (QDBool(kQDBlockShake) && motion == UIEventSubtypeMotionShake) {
        return;
    }
    %orig;
}

- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion {
    if (QDBool(kQDBlockTeen) && [vc isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)vc;
        NSString *text = [NSString stringWithFormat:@"%@ %@", alert.title ?: @"", alert.message ?: @""];
        NSArray *words = @[ @"青少年", @"未成年", @"护眼提醒", @"家长" ];
        BOOL blocked = NO;
        for (NSString *w in words) {
            if ([text containsString:w]) {
                blocked = YES;
                break;
            }
        }
        if (blocked) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [DYYYUtils showToast:@"已拦截青少年模式弹窗"];
            });
            if (completion) completion();
            return;
        }
    }
    %orig;
}

%end

%hook UIScreen

- (BOOL)isCaptured {
    if (QDBool(kQDBlockCapture)) return NO;
    return %orig;
}

%end

%hook UIImpactFeedbackGenerator

- (void)impactOccurred {
    if (QDBool(kQDDisableHaptic)) return;
    %orig;
}

- (void)impactOccurredWithIntensity:(CGFloat)intensity {
    if (QDBool(kQDDisableHaptic)) return;
    %orig;
}

%end

#pragma mark - 启动

%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;
    QDExtraRegisterDefaults();
    dispatch_async(dispatch_get_main_queue(), ^{
        QDApplyCachePolicy();
        QDDisableRemoteCommands();
        QDApplyPreloadPolicy();
    });
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    if (QDBool(kQDBlockIsland)) {
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
        QDDisableRemoteCommands();
    }
}

%end

#pragma mark - 设置页

static NSArray<NSArray<NSString *> *> *QDSystemSpecs(void) {
    static NSArray *specs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        specs = @[
            @[ @"灵动岛屏蔽", kQDBlockIsland, @"禁止抖音在灵动岛 / 锁屏弹出「正在播放」" ],
            @[ @"减少预加载", kQDReducePreload, @"压低视频预加载数量，滑动更稳、更省内存" ],
            @[ @"低内存模式", kQDTurboCache, @"收紧网络缓存上限，长时间刷视频不易掉帧" ],
            @[ @"关闭毛玻璃", kQDDisableBlur, @"关掉大屏毛玻璃换帧率（会改变观感）" ],
            @[ @"屏蔽摇一摇", kQDBlockShake, @"拦截摇一摇触发的广告与跳转" ],
            @[ @"屏蔽录屏检测", kQDBlockCapture, @"让抖音检测不到正在录屏 / 截屏" ],
            @[ @"拦截青少年弹窗", kQDBlockTeen, @"自动拦掉青少年模式相关弹窗" ],
            @[ @"关闭触感反馈", kQDDisableHaptic, @"关掉震动反馈（省电，手感偏生硬）" ],
        ];
    });
    return specs;
}

@implementation QDExtra

+ (void)registerDefaults {
    QDExtraRegisterDefaults();
}

+ (AWESettingBaseViewController *)systemViewController {
    NSMutableDictionary *handlers = [NSMutableDictionary dictionary];

    NSMutableArray<AWESettingItemModel *> *sysItems = [NSMutableArray array];
    for (NSArray<NSString *> *spec in QDSystemSpecs()) {
        AWESettingItemModel *item = [DYYYSettingsHelper createSettingItem:@{
            @"identifier" : spec[1],
            @"title" : spec[0],
            @"subTitle" : spec[2],
            @"detail" : @"",
            @"cellType" : @37,
            @"imageName" : @"ic_lightning_outlined_20"
        }
                                                          cellTapHandlers:handlers];
        [sysItems addObject:item];
    }

    AWESettingSectionModel *sysSection =
        [DYYYSettingsHelper createSectionWithTitle:@"灵动岛与性能"
                                       footerTitle:@"灵动岛屏蔽默认开启：抖音更新「正在播放」信息时会被丢弃，灵动岛不再展开。除「减少预加载」外，全部改动即时生效。"
                                             items:sysItems];
    return [DYYYSettingsHelper createSubSettingsViewController:@"系统与性能" sections:@[ sysSection ]];
}

@end

%ctor {
    QDExtraRegisterDefaults();
}
