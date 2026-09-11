//
//  QDGlassTabBar.xm
//  YTT 液态玻璃 — 双引擎
//
//  引擎 A · 悬浮胶囊（iOS 26+ 默认）
//  ---------------------------------------------------------------------------
//  iOS 26 的系统 UITabBar 原生就是「悬浮液态玻璃胶囊」：圆角、留边、选中项放大成
//  带文字的胶囊并带滑动动画，全是 UIKit 自己画的。所以做法是：
//    · 自建 UITabBar 挂进抖音底栏（随父视图显隐/位移，不碰抖音布局）；
//    · 镜像抖音的 4 个 tab + 拍摄入口（加号内联在中间，与原版一致，绝不单独成圆）；
//    · 点击原样转发给抖音按钮自己的回调（tabBarButtonDidTouchUpInside: /
//      plusTabBarButtonDidClick:），抖音只认它自己的回调，直接写 selectedIndex 会被吞；
//    · 抖音底栏内容（背景层 + 按钮）layer.opacity 置 0，但不动 hidden/alpha/frame，
//      位置、安全区、显隐状态全部保持抖音原样 —— 因此不会再出现按钮跑偏。
//
//  引擎 B · 原地换皮（旧系统回退）
//  ---------------------------------------------------------------------------
//  只换材质不动布局：把底栏现成的毛玻璃层换成 UIGlassEffect / 系统材质。
//
//  铁律（改动前先读）
//  ---------------------------------------------------------------------------
//  1. 绝不用 __IPHONE_OS_VERSION_MAX_ALLOWED 门控 —— 打包 SDK 低于 26 时整段会被剔除，
//     表现为「液态玻璃一点效果都没有」。全部运行时探测。
//  2. 所有写入先比较再写；驱动点 layoutSubviews 是逐帧路径。
//  3. 切页必须转发抖音按钮回调，直接写 selectedIndex 无效。
//  4. 拍摄按钮 type == 2，不参与 selectedIndex，validIndex 恒为 0。
//

#import "QDGlassTabBar.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "AwemeHeaders.h"
#import "DYYYUtils.h"

#pragma mark - 偏好键

// 与 YTT 旧的独立插件共用同一批键名，老用户升级后开关状态不丢。
static NSString *const kQDYTTKeyGlass     = @"YTT.glass";
static NSString *const kQDYTTKeyClear     = @"YTT.clear";
static NSString *const kQDYTTKeyGradient  = @"YTT.gradient";
static NSString *const kQDYTTKeyCapsule   = @"YTT.capsule";
static NSString *const kQDYTTKeyExtend    = @"YTT.extend";
static NSString *const kQDYTTKeyFloating  = @"YTT.floating";
static NSString *const kQDYTTKeyAutoTint  = @"YTT.autotint";   // 首页视频全屏播放：底栏颜色自动跟随视频画面

void QDYTTGlassRegisterDefaults(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            kQDYTTKeyGlass    : @YES,   // 主开关默认开：装上就该看得见
            kQDYTTKeyClear    : @YES,   // Clear 档透亮玻璃：黑底上不再发灰白（用户明确要透亮）
            kQDYTTKeyGradient : @YES,   // 摘掉压暗玻璃的渐变，是玻璃观感的一部分
            kQDYTTKeyCapsule  : @NO,    // 仅引擎 B 的装饰胶囊，默认关
            kQDYTTKeyExtend   : @YES,   // 视频透出底栏：底栏后面是画面而不是黑块（用户明确要的）
            kQDYTTKeyFloating : @YES,   // iOS 26+ 默认走悬浮胶囊引擎
            kQDYTTKeyAutoTint : @YES,   // 首页视频全屏播放：底栏颜色自动跟随视频，不再一直黑
        }];
    });
}

static BOOL QDYTTBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

BOOL QDYTTGlassEnabled(void)         { return QDYTTBool(kQDYTTKeyGlass); }
BOOL QDYTTGlassClearEnabled(void)    { return QDYTTBool(kQDYTTKeyClear); }
BOOL QDYTTGlassGradientEnabled(void) { return QDYTTBool(kQDYTTKeyGradient); }
BOOL QDYTTGlassCapsuleEnabled(void)  { return QDYTTBool(kQDYTTKeyCapsule); }
BOOL QDYTTGlassExtendEnabled(void)   { return QDYTTBool(kQDYTTKeyExtend); }
BOOL QDYTTGlassFloatingEnabled(void) { return QDYTTBool(kQDYTTKeyFloating); }
BOOL QDYTTAutoTintEnabled(void)      { return QDYTTBool(kQDYTTKeyAutoTint); }

#pragma mark - 状态（给设置页读）

static __weak UIView *gQDBar = nil;
static NSString *gQDBarClassName = nil;
static BOOL gQDBarGlassApplied = NO;
static BOOL gQDToastShown = NO;
static NSString *gQDLastFailReason = nil;
static BOOL gQDFloatActive = NO;      // 当前是否处于悬浮胶囊引擎
static CFTimeInterval gQDLastTick = 0;  // 底栏树遍历节流时间戳

// —— 悬浮胶囊引擎的运行时状态 ——
static UITabBar *gFloatBar = nil;                 // 自建的系统 UITabBar（iOS 26+ 自带液态玻璃胶囊）
static id gFloatProxy = nil;                      // 它的 delegate
static NSArray<NSNumber *> *gFloatKinds = nil;    // 与 items 同序；-1 = 拍摄
static NSArray *gFloatButtons = nil;              // 与 items 同序的抖音原始按钮
static NSString *gFloatSignature = nil;           // 条目签名，变化才重建
static UITabBarItem *gFloatLastItem = nil;        // 拍摄点击后选择态弹回这里
static __weak UIView *gFloatHost = nil;           // 宿主抖音底栏

// 同样不能依赖编译期 SDK 版本，直接问运行时有没有这个类。
BOOL QDYTTGlassNativeAvailable(void) {
    return NSClassFromString(@"UIGlassEffect") != nil;
}

NSString *QDYTTGlassEngineName(void) {
    if (!QDYTTGlassNativeAvailable()) return @"降级毛玻璃（旧系统）";
    return gQDFloatActive ? @"原生液态玻璃 · 悬浮胶囊" : @"原生 UIGlassEffect";
}

NSString *QDYTTGlassBarStatus(void) {
    if (!QDYTTGlassEnabled()) return @"已关闭";
    if (gQDBar && gQDBar.window) {
        return [NSString stringWithFormat:@"已接管 · %@ · %@",
                gQDBarClassName ?: @"底栏",
                gQDBarGlassApplied ? QDYTTGlassEngineName() : @"材质替换未生效"];
    }
    if (gQDLastFailReason) return [NSString stringWithFormat:@"未接管 · %@", gQDLastFailReason];
    return @"未找到底栏（切到首页再回来看）";
}

#pragma mark - 关联键

static char kQDOrigEffectKey;
static char kQDOrigHiddenKey;
static char kQDOrigBGKey;
static char kQDGlassMarkKey;
static char kQDAddedGlassKey;
static char kQDCapsuleKey;
static char kQDOrigFrameKey;

#pragma mark - 小工具

static BOOL QDYTTNameContains(UIView *view, NSString *needle) {
    if (!view || needle.length == 0) return NO;
    return [NSStringFromClass(view.class) containsString:needle];
}

static CGFloat QDYTTRectArea(CGRect rect) {
    return MAX(0.0, rect.size.width) * MAX(0.0, rect.size.height);
}

static id QDYTTKVC(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

/// 子树里是否含有可交互控件。含控件的视图是内容层，绝不能被当成「面纱」处理。
static BOOL QDYTTContainsControl(UIView *root, int depth) {
    if (!root || depth > 4) return NO;
    int budget = 400;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count > 0 && budget-- > 0) {
        UIView *node = stack.lastObject;
        [stack removeLastObject];
        if (node != root && [node isKindOfClass:[UIControl class]]) return YES;
        if (depth >= 0) {
            for (UIView *sub in node.subviews) {
                if (stack.count > 300) break;
                [stack addObject:sub];
            }
        }
    }
    return NO;
}

/// 底栏里的 tab 按钮数组。KVC 优先，失败再按类名扫子树。
/// 底栏按钮必须按视觉左右顺序排列：KVC 拿到的数组通常有序，但 BFS 兜底路径
/// 按层级遍历，顺序可能与屏幕上不一致——顺序错了「朋友 / 消息」就会左右错位。
static NSArray *QDYTTButtonsSortedByX(NSArray *buttons) {
    if (buttons.count < 2) return buttons;
    return [buttons sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        CGFloat ax = [a isKindOfClass:[UIView class]] ? ((UIView *)a).frame.origin.x : 0;
        CGFloat bx = [b isKindOfClass:[UIView class]] ? ((UIView *)b).frame.origin.x : 0;
        if (ax < bx) return NSOrderedAscending;
        if (ax > bx) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

static NSArray *QDYTTBarButtons(UIView *bar) {
    static NSArray<NSString *> *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[ @"tabBarButtons", @"buttons" ];
    });

    for (NSString *key in keys) {
        id value = QDYTTKVC(bar, key);
        if ([value isKindOfClass:[NSArray class]] && [(NSArray *)value count] >= 2) return QDYTTButtonsSortedByX(value);
    }
    id controller = QDYTTKVC(bar, @"yy_viewController");
    for (NSString *key in keys) {
        id value = QDYTTKVC(controller, key);
        if ([value isKindOfClass:[NSArray class]] && [(NSArray *)value count] >= 2) return QDYTTButtonsSortedByX(value);
    }

    NSMutableArray *found = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:bar];
    int budget = 600;
    int depth = 0;
    while (stack.count > 0 && budget-- > 0 && depth < 6) {
        NSUInteger count = stack.count;
        for (NSUInteger i = 0; i < count; i++) {
            UIView *node = stack[i];
            if (node != bar
                && QDYTTNameContains(node, @"TabBar")
                && QDYTTNameContains(node, @"Button")) {
                [found addObject:node];
                continue;
            }
            [stack addObjectsFromArray:node.subviews];
        }
        [stack removeObjectsInRange:NSMakeRange(0, count)];
        depth++;
    }
    return found.count >= 2 ? QDYTTButtonsSortedByX(found) : nil;
}

/// 底栏里子视图的「内容区」——按钮所在的容器，玻璃要垫在它下面。
static UIView *QDYTTBarContentHost(UIView *bar, NSArray *buttons) {
    UIView *first = buttons.firstObject;
    if (!first) return nil;
    UIView *host = first;
    while (host.superview && host.superview != bar) host = host.superview;
    return host;
}

#pragma mark - 底栏发现（几何 + 类名评分，不硬编码单一类名）

static NSInteger QDYTTBarScore(UIView *view, CGRect windowBounds) {
    if (!view || view.window == nil) return -1;
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"Window"]) return -1;
    if ([name containsString:@"Scroll"] || [name containsString:@"Collection"]
        || [name containsString:@"Table"]) return -1;

    CGRect r = [view convertRect:view.bounds toView:nil];
    if (r.size.width < windowBounds.size.width * 0.55) return -1;
    if (r.size.height < 24.0 || r.size.height > 220.0) return -1;
    if (CGRectGetMaxY(r) < windowBounds.size.height - 14.0) return -1;
    if (CGRectGetMinY(r) < windowBounds.size.height * 0.5) return -1;

    NSInteger score = 0;
    if ([name containsString:@"NormalModeTabBar"]) score += 140;
    else if ([name containsString:@"TabBar"]) score += 60;
    if (QDYTTBarButtons(view).count >= 3) score += 40;
    if ([name containsString:@"BasicModeTabBar"]) score -= 60;   // 极速版底栏，正常版不该选它
    return score;
}

static UIView *QDYTTFindBarInView(UIView *root, CGRect windowBounds, NSInteger *bestScore) {
    UIView *best = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    int budget = 9000;
    while (queue.count > 0 && budget-- > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];

        NSInteger score = QDYTTBarScore(node, windowBounds);
        if (score > *bestScore) {
            *bestScore = score;
            best = node;
        }
        if (node.subviews.count > 80) continue;
        [queue addObjectsFromArray:node.subviews];
    }
    return best;
}

static UIView *QDYTTFindBar(void) {
    CGRect windowBounds = CGRectZero;
    UIWindow *target = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.hidden || window.alpha < 0.01) continue;
        if (window.bounds.size.width < 100) continue;
        if (window.bounds.size.width > windowBounds.size.width) {
            windowBounds = window.bounds;
            target = window;
        }
    }
    if (!target) return nil;

    NSInteger bestScore = 40;   // 门槛：至少要像一条底栏
    return QDYTTFindBarInView(target, windowBounds, &bestScore);
}

#pragma mark - 引擎 B：材质

static UIColor *QDYTTAccentColor(void) {
    return [UIColor colorWithRed:0.15 green:0.65 blue:0.72 alpha:1.0];
}

// 重要：绝不要用 __IPHONE_OS_VERSION_MAX_ALLOWED 包这段逻辑。
// 打包用的 SDK 通常还不到 iOS 26，一旦被编译期开关挡掉，这里就永远只会走降级毛玻璃，
// 用户看到的就是「液态玻璃一点效果都没有」。全部改成运行时探测，SDK 版本无关。
static UIVisualEffect *QDYTTMakeEffect(void) {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    if (glassClass) {
        id effect = nil;
        @try {
            SEL styleSel = NSSelectorFromString(@"effectWithStyle:");
            if ([glassClass respondsToSelector:styleSel]) {
                // UIGlassEffectStyle: Regular = 0, Clear = 1
                NSInteger style = QDYTTGlassClearEnabled() ? 1 : 0;
                effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)((id)glassClass, styleSel, style);
            }
            if (!effect) effect = [[glassClass alloc] init];
        } @catch (__unused NSException *e) {
            effect = nil;
        }

        if (effect) {
            @try {
                if (QDYTTGlassClearEnabled() && [effect respondsToSelector:@selector(setTintColor:)]) {
                    [effect setValue:[UIColor colorWithWhite:0 alpha:0.06] forKey:@"tintColor"];
                }
                if ([effect respondsToSelector:@selector(setInteractive:)]) {
                    [effect setValue:@YES forKey:@"interactive"]; // 按压形变，液态玻璃的「活」感来源
                }
            } @catch (__unused NSException *e) {
            }
            return effect;
        }
    }
    // 旧系统 / 取不到原生玻璃：系统级材质毛玻璃，观感最接近，且永远不会是「什么都没有」。
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

static BOOL QDYTTIsGlassEffect(UIVisualEffect *effect) {
    if (!effect) return NO;
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    return glassClass && [effect isKindOfClass:glassClass];
}

#pragma mark - 引擎 B：面纱（压暗玻璃的渐变 / 实色底）处理

/// 把铺满底栏、不透明的「面纱」压掉。只动视觉，不动布局，也绝不碰含控件的层。
static void QDYTTNeutralizeVeils(UIView *bar) {
    if (!bar) return;
    CGFloat barW = bar.bounds.size.width;
    CGFloat barH = bar.bounds.size.height;
    if (barW < 1.0 || barH < 1.0) return;

    if (bar.backgroundColor && CGColorGetAlpha(bar.backgroundColor.CGColor) > 0.02) {
        if (!objc_getAssociatedObject(bar, &kQDOrigBGKey)) {
            objc_setAssociatedObject(bar, &kQDOrigBGKey, bar.backgroundColor,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        bar.backgroundColor = [UIColor clearColor];
    }

    for (UIView *sub in bar.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]]) continue;
        if (objc_getAssociatedObject(sub, &kQDAddedGlassKey)) continue;
        if (sub == (UIView *)gFloatBar) continue;
        CGRect f = sub.frame;
        if (f.size.width < barW * 0.9 || f.size.height < barH * 0.45) continue;
        // 按钮所在的内容容器必须留着——藏了它整条底栏就空了。
        if (QDYTTContainsControl(sub, 0)) continue;

        BOOL looksLikeVeil = QDYTTNameContains(sub, @"Gradient")
                          || QDYTTNameContains(sub, @"Shadow")
                          || QDYTTNameContains(sub, @"Backdrop")
                          || QDYTTNameContains(sub, @"Dimming")
                          || QDYTTNameContains(sub, @"Mask");

        if (looksLikeVeil && !sub.hidden) {
            if (!objc_getAssociatedObject(sub, &kQDOrigHiddenKey)) {
                objc_setAssociatedObject(sub, &kQDOrigHiddenKey, @(sub.hidden),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            sub.hidden = YES;
            continue;
        }
        // 实色满幅底：只清色，不动显隐（有些是抖音的布局垫层，藏了会塌）。
        if (sub.backgroundColor && CGColorGetAlpha(sub.backgroundColor.CGColor) > 0.02) {
            if (!objc_getAssociatedObject(sub, &kQDOrigBGKey)) {
                objc_setAssociatedObject(sub, &kQDOrigBGKey, sub.backgroundColor,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            sub.backgroundColor = [UIColor clearColor];
        }
    }
}

static void QDYTTRestoreVeils(UIView *bar) {
    if (!bar) return;
    id bg = objc_getAssociatedObject(bar, &kQDOrigBGKey);
    if (bg) {
        bar.backgroundColor = [bg isKindOfClass:[UIColor class]] ? bg : nil;
        objc_setAssociatedObject(bar, &kQDOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *sub in bar.subviews) {
        id hidden = objc_getAssociatedObject(sub, &kQDOrigHiddenKey);
        if (hidden) {
            sub.hidden = [hidden boolValue];
            objc_setAssociatedObject(sub, &kQDOrigHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        id original = objc_getAssociatedObject(sub, &kQDOrigBGKey);
        if (original) {
            sub.backgroundColor = [original isKindOfClass:[UIColor class]] ? original : nil;
            objc_setAssociatedObject(sub, &kQDOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

#pragma mark - 引擎 B：玻璃接管

/// 收集底栏里「可能承载背景材质」的视图：KVC 命名槽位 + 子树扫描。
static void QDYTTCollectBackdrops(UIView *bar,
                                  NSMutableArray<UIVisualEffectView *> *effectViews,
                                  NSMutableArray<UIView *> *plainBackdrops) {
    static NSArray<NSString *> *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[ @"awe_blurView", @"backgroundView", @"groundGlassView", @"glassView",
                  @"blurView", @"tabBarBlurView", @"gradientView", @"backgroundImageView",
                  @"skinContainerView", @"separatorLine" ];
    });
    for (NSString *key in keys) {
        UIView *candidate = QDYTTKVC(bar, key);
        if (![candidate isKindOfClass:[UIView class]] || candidate == bar) continue;
        if ([candidate isKindOfClass:[UIVisualEffectView class]]) {
            if (![effectViews containsObject:(UIVisualEffectView *)candidate]) {
                [effectViews addObject:(UIVisualEffectView *)candidate];
            }
        } else if (![plainBackdrops containsObject:candidate]) {
            [plainBackdrops addObject:candidate];
        }
    }

    // 子树扫描兜底：只收「占底栏面积 30% 以上」的毛玻璃层，避免把按钮自带的小毛玻璃算进来。
    CGFloat barArea = QDYTTRectArea(bar.bounds);
    if (barArea < 1.0) return;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:bar];
    int budget = 800;
    int depth = 0;
    while (stack.count > 0 && budget-- > 0 && depth < 4) {
        NSUInteger count = stack.count;
        for (NSUInteger i = 0; i < count; i++) {
            UIView *node = stack[i];
            if ([node isKindOfClass:[UIVisualEffectView class]]) {
                if (QDYTTRectArea(node.bounds) >= barArea * 0.3
                    && ![effectViews containsObject:(UIVisualEffectView *)node]) {
                    [effectViews addObject:(UIVisualEffectView *)node];
                }
                continue;   // 不往毛玻璃里再钻
            }
            [stack addObjectsFromArray:node.subviews];
        }
        [stack removeObjectsInRange:NSMakeRange(0, count)];
        depth++;
    }
}

/// 真正给一个毛玻璃层换上官方玻璃材质。同一个 view，同一个 frame，同一个 z 序 —— 零重排。
static BOOL QDYTTGlassEffectView(UIVisualEffectView *view) {
    if (!view) return NO;
    if (objc_getAssociatedObject(view, &kQDGlassMarkKey)) {
        return QDYTTIsGlassEffect(view.effect);   // 已接管，不重复写（写多了会打断系统的呈现过渡）
    }
    if (!objc_getAssociatedObject(view, &kQDOrigEffectKey)) {
        objc_setAssociatedObject(view, &kQDOrigEffectKey, view.effect ?: [NSNull null],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIVisualEffect *glass = QDYTTMakeEffect();
    if (!glass) return NO;
    view.effect = glass;
    view.userInteractionEnabled = NO;   // 玻璃层不该吃触摸
    objc_setAssociatedObject(view, &kQDGlassMarkKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return QDYTTIsGlassEffect(view.effect) || glass != nil;
}

static void QDYTTUnglassEffectView(UIVisualEffectView *view) {
    if (!view) return;
    id original = objc_getAssociatedObject(view, &kQDOrigEffectKey);
    if (original) {
        view.effect = [original isKindOfClass:[NSNull class]] ? nil : (UIVisualEffect *)original;
        objc_setAssociatedObject(view, &kQDOrigEffectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(view, &kQDGlassMarkKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/// 找不到任何现成毛玻璃层时，在底栏最底层补一块玻璃。
/// 注意：垫在内容容器「下面」，不是盖在上面，所以按钮与外框位置分毫不动。
static UIVisualEffectView *QDYTTEnsureOwnGlass(UIView *bar, NSArray *buttons) {
    UIVisualEffectView *glass = objc_getAssociatedObject(bar, &kQDAddedGlassKey);
    if (!glass || glass.superview != bar) {
        glass = [[UIVisualEffectView alloc] initWithEffect:QDYTTMakeEffect()];
        glass.userInteractionEnabled = NO;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.frame = bar.bounds;
        objc_setAssociatedObject(bar, &kQDAddedGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    glass.frame = bar.bounds;   // 尺寸跟着底栏走，越界会被抖音的重排覆盖，所以逐帧比对

    UIView *host = QDYTTBarContentHost(bar, buttons);
    if (host && host.superview == bar) {
        NSUInteger index = [bar.subviews indexOfObject:host];
        if (index != NSNotFound && bar.subviews[index] != glass) {
            [bar insertSubview:glass atIndex:index];
        }
    } else if (glass.superview != bar) {
        [bar insertSubview:glass atIndex:0];
    }
    return glass;
}

static void QDYTTRemoveOwnGlass(UIView *bar) {
    id glass = objc_getAssociatedObject(bar, &kQDAddedGlassKey);
    if ([glass isKindOfClass:[UIView class]]) [glass removeFromSuperview];
    objc_setAssociatedObject(bar, &kQDAddedGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 引擎 B：选中玻璃胶囊（装饰，默认关闭）

static void QDYTTUpdateCapsule(UIView *bar, NSArray *buttons) {
    UIVisualEffectView *capsule = objc_getAssociatedObject(bar, &kQDCapsuleKey);

    if (!QDYTTGlassCapsuleEnabled() || !QDYTTGlassEnabled() || buttons.count < 3) {
        if (capsule) {
            [capsule removeFromSuperview];
            objc_setAssociatedObject(bar, &kQDCapsuleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    id controller = QDYTTKVC(bar, @"yy_viewController");
    NSInteger selected = -1;
    @try {
        if ([controller isKindOfClass:[UITabBarController class]]) {
            selected = (NSInteger)((UITabBarController *)controller).selectedIndex;
        }
    } @catch (__unused NSException *exception) {}

    UIView *target = nil;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        id button = buttons[i];
        if (![button isKindOfClass:[UIView class]]) continue;
        UIView *view = (UIView *)button;
        if (view.hidden || view.alpha < 0.01) continue;
        // 中间那颗是「+」（拍摄入口，不参与 selectedIndex），胶囊必须跳过它，否则会盖住加号。
        if (i == buttons.count / 2) continue;
        NSInteger validIndex = -1;
        @try {
            validIndex = [[button valueForKey:@"validIndex"] integerValue];
        } @catch (__unused NSException *exception) {
            validIndex = -1;
        }
        if (validIndex == selected) { target = view; break; }
    }
    if (!target) {
        if (capsule) capsule.hidden = YES;
        return;
    }

    if (!capsule) {
        capsule = [[UIVisualEffectView alloc] initWithEffect:QDYTTMakeEffect()];
        capsule.userInteractionEnabled = NO;
        capsule.alpha = 1.0;
        objc_setAssociatedObject(bar, &kQDCapsuleKey, capsule, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    capsule.hidden = NO;

    UIView *host = QDYTTBarContentHost(bar, buttons);
    if (host && host.superview == bar && capsule.superview != bar) {
        NSUInteger index = [bar.subviews indexOfObject:host];
        [bar insertSubview:capsule atIndex:(index == NSNotFound ? 0 : index)];
    } else if (capsule.superview != bar) {
        [bar insertSubview:capsule atIndex:0];
    }

    CGRect rect = [target convertRect:target.bounds toView:bar];
    if (rect.size.width < 1.0 || rect.size.height < 1.0) return;
    rect = CGRectInset(rect, -2.0, -2.0);
    CGFloat radius = MIN(rect.size.height, rect.size.width) * 0.5;

    if (!CGRectEqualToRect(capsule.frame, rect)) {
        capsule.frame = rect;
        if ([capsule respondsToSelector:@selector(setCornerConfiguration:)]) {
            Class configClass = NSClassFromString(@"UICornerConfiguration");
            if (configClass && [configClass respondsToSelector:@selector(capsuleConfiguration)]) {
                capsule.cornerConfiguration = [configClass performSelector:@selector(capsuleConfiguration)];
            }
        }
    }
    if (capsule.layer.cornerRadius != radius) {
        capsule.layer.cornerRadius = radius;
        capsule.clipsToBounds = YES;
    }
}

#pragma mark - 引擎 B：背景延伸（视频透出底栏）

static __weak UIView *gQDExtendTarget = nil;

static void QDYTTExtendStop(void) {
    UIView *target = gQDExtendTarget;
    if (target) {
        NSValue *original = objc_getAssociatedObject(target, &kQDOrigFrameKey);
        if (original) {
            CGRect frame = original.CGRectValue;
            if (!CGRectEqualToRect(target.frame, frame)) {
                CGFloat height = frame.size.height;
                frame = target.frame;
                frame.size.height = height;
                target.frame = frame;
            }
            objc_setAssociatedObject(target, &kQDOrigFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    gQDExtendTarget = nil;
}

static NSInteger QDYTTWorkScore(UIView *view, CGRect windowBounds) {
    if (!view || view.window == nil) return -1;
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"Window"]) return -200;
    if (QDYTTNameContains(view, @"Scroll") || QDYTTNameContains(view, @"Collection")
        || QDYTTNameContains(view, @"Table")) return -70;
    if ([view isKindOfClass:[UIVisualEffectView class]]) return -40;

    // 硬门槛：只有真正的视频画面允许被拉伸。文案/评论区/整个作品容器绝不能拉伸——
    // 拉了它们，文案就会跟着画面一起沉到悬浮底栏下面，表现为「文字跟底栏重合」。
    BOOL isVideoSurface = QDYTTNameContains(view, @"Video") || QDYTTNameContains(view, @"Player");
    if (!isVideoSurface) return -1;
    if (QDYTTNameContains(view, @"Caption") || QDYTTNameContains(view, @"Description")
        || QDYTTNameContains(view, @"Container") || QDYTTNameContains(view, @"Cell")
        || QDYTTNameContains(view, @"Detail") || QDYTTNameContains(view, @"Text")) return -1;

    CGRect r = [view convertRect:view.bounds toView:nil];
    if (r.size.width < windowBounds.size.width * 0.6) return -1;
    if (r.size.height < windowBounds.size.height * 0.3) return -1;

    NSInteger score = 0;
    if (QDYTTNameContains(view, @"Video") || QDYTTNameContains(view, @"Player")
        || QDYTTNameContains(view, @"FeedView") || QDYTTNameContains(view, @"FeedCell")
        || QDYTTNameContains(view, @"AwemeView")) score += 120;
    if (r.size.width >= windowBounds.size.width * 0.85) score += 30;
    if (r.size.height >= windowBounds.size.height * 0.6) score += 30;
    if (CGRectGetMaxY(r) >= windowBounds.size.height - 120.0) score += 20;
    if (CGRectGetMinY(r) <= windowBounds.size.height * 0.25) score += 20;
    return score;
}

static void QDYTTExtendApply(void) {
    if (!QDYTTGlassExtendEnabled() || !QDYTTGlassEnabled()) {
        QDYTTExtendStop();
        return;
    }
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return;
    CGRect windowBounds = window.bounds;
    if (windowBounds.size.width > windowBounds.size.height) return;   // 只处理竖屏

    UIView *best = nil;
    NSInteger bestScore = 80;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    int budget = 6000;
    while (queue.count > 0 && budget-- > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSInteger score = QDYTTWorkScore(node, windowBounds);
        if (score > bestScore) {
            bestScore = score;
            best = node;
        }
        if (node.subviews.count > 60) continue;
        [queue addObjectsFromArray:node.subviews];
    }
    if (!best) { QDYTTExtendStop(); return; }

    if (gQDExtendTarget && gQDExtendTarget != best) QDYTTExtendStop();
    gQDExtendTarget = best;

    UIView *parent = best.superview;
    if (!parent) return;

    CGFloat bottom = [window convertPoint:CGPointMake(0, CGRectGetMaxY(windowBounds)) toView:parent].y;
    CGFloat current = CGRectGetMaxY(best.frame);
    if (bottom <= current + 2.0) return;   // 容差 2pt：否则会和抖音的 Auto Layout 来回打架

    if (!objc_getAssociatedObject(best, &kQDOrigFrameKey)) {
        objc_setAssociatedObject(best, &kQDOrigFrameKey, [NSValue valueWithCGRect:best.frame],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect frame = best.frame;
    frame.size.height = bottom - CGRectGetMinY(frame);
    best.frame = frame;
}

#pragma mark - 首页视频全屏播放：底栏颜色自动跟随视频画面

// 采样当前视频帧的平均色（缩到 10x10 求均值），垫一层同色洗色层在视频底部、
// 悬浮玻璃后面——玻璃透出的就是视频的颜色，画面变了底栏颜色跟着变。
static void QDYTTAutoTintApply(UIView *video) {
    if (!video || !video.window) return;

    UIView *wash = objc_getAssociatedObject(video, "qd_tint_wash");
    if (!wash) {
        wash = [[UIView alloc] init];
        wash.userInteractionEnabled = NO;
        wash.translatesAutoresizingMaskIntoConstraints = NO;
        [video addSubview:wash];
        [wash.leadingAnchor constraintEqualToAnchor:video.leadingAnchor].active = YES;
        [wash.trailingAnchor constraintEqualToAnchor:video.trailingAnchor].active = YES;
        [wash.bottomAnchor constraintEqualToAnchor:video.bottomAnchor].active = YES;
        [wash.heightAnchor constraintEqualToConstant:140].active = YES;
        objc_setAssociatedObject(video, "qd_tint_wash", wash, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 采样时把洗色层暂时隐藏，避免「采样到自己的颜色」正反馈
    wash.hidden = YES;
    UIGraphicsImageRendererFormat *fmt = [[UIGraphicsImageRendererFormat alloc] init];
    fmt.scale = 1.0;
    fmt.opaque = YES;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(10, 10) format:fmt];
    UIImage *snap = [r imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
        [video drawViewHierarchyInRect:video.bounds afterScreenUpdates:NO];
    }];
    wash.hidden = NO;
    CGImageRef cg = snap.CGImage;
    if (!cg) return;

    unsigned char px[400];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bmp = CGBitmapContextCreate(px, 10, 10, 8, 40, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (!bmp) { CGColorSpaceRelease(cs); return; }
    CGContextDrawImage(bmp, CGRectMake(0, 0, 10, 10), cg);
    CGContextRelease(bmp);
    CGColorSpaceRelease(cs);

    long rSum = 0, gSum = 0, bSum = 0;
    for (int i = 0; i < 100; i++) {
        rSum += px[i * 4];
        gSum += px[i * 4 + 1];
        bSum += px[i * 4 + 2];
    }
    CGFloat rr = rSum / 100.0 / 255.0, gg = gSum / 100.0 / 255.0, bb = bSum / 100.0 / 255.0;

    // 与上次颜色几乎一样就跳过，避免反复动画
    UIColor *prev = objc_getAssociatedObject(video, "qd_tint_color");
    if (prev) {
        CGFloat pr = 0, pg = 0, pb = 0, pa = 0;
        [prev getRed:&pr green:&pg blue:&pb alpha:&pa];
        if (fabs(pr - rr) < 0.04 && fabs(pg - gg) < 0.04 && fabs(pb - bb) < 0.04) return;
    }
    UIColor *next = [UIColor colorWithRed:rr green:gg blue:bb alpha:0.55];
    objc_setAssociatedObject(video, "qd_tint_color", next, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView transitionWithView:wash duration:0.6 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        wash.backgroundColor = next;
    } completion:nil];
}

static void QDYTTAutoTintSweep(void) {
    // 关了开关：把还挂着的洗色层清掉
    if (!QDYTTAutoTintEnabled() || !QDYTTGlassEnabled()) {
        UIWindow *window = [DYYYUtils getActiveWindow];
        if (window) {
            NSMutableArray<UIView *> *q = [NSMutableArray arrayWithObject:window];
            int budget = 3000;
            while (q.count > 0 && budget-- > 0) {
                UIView *n = q.firstObject;
                [q removeObjectAtIndex:0];
                UIView *wash = objc_getAssociatedObject(n, "qd_tint_wash");
                if (wash) {
                    [wash removeFromSuperview];
                    objc_setAssociatedObject(n, "qd_tint_wash", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(n, "qd_tint_color", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                if (n.subviews.count > 60) continue;
                [q addObjectsFromArray:n.subviews];
            }
        }
        return;
    }

    // 找当前视频画面（与背景延伸同一套打分逻辑）
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) return;
    CGRect windowBounds = window.bounds;
    if (windowBounds.size.width > windowBounds.size.height) return;   // 只处理竖屏

    UIView *best = nil;
    NSInteger bestScore = 80;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    int budget = 4000;
    while (queue.count > 0 && budget-- > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSInteger score = QDYTTWorkScore(node, windowBounds);
        if (score > bestScore) {
            bestScore = score;
            best = node;
        }
        if (node.subviews.count > 60) continue;
        [queue addObjectsFromArray:node.subviews];
    }
    if (best) QDYTTAutoTintApply(best);
}

#pragma mark - 引擎 A：悬浮胶囊（iOS 26+）

// 抖音私有符号集中在此，改名时只改这里。
static NSString * const kQDTabClickSelector  = @"tabBarButtonDidTouchUpInside:gestureRecognizer:";
static NSString * const kQDPlusClickSelector = @"plusTabBarButtonDidClick:";
static NSString * const kQDBadgeContainerClass = @"AWENormalModeTabBarBadgeContainerView";
static NSString * const kQDBadgeClass = @"DUXBadge";
// 抖音按钮 type：2 = 拍摄入口（不参与 selectedIndex）。
static const long long kQDPlusButtonType = 2;

static UITabBarController *QDFloatControllerForView(UIView *view) {
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:[UITabBarController class]]) return (UITabBarController *)r;
    }
    return nil;
}

static NSString *QDFloatButtonTitle(id button) {
    id inner = QDYTTKVC(button, @"innerView");
    NSString *text = QDYTTKVC(QDYTTKVC(inner, @"label"), @"text");
    if (text.length > 0) return text;
    text = QDYTTKVC(inner, @"currentTitleText");
    if (text.length > 0) return text;
    text = QDYTTKVC(button, @"currentTitleText");
    if (text.length > 0) return text;
    if ([button isKindOfClass:[UIView class]]) {
        NSString *a11y = [(UIView *)button accessibilityLabel];
        if (a11y.length > 0 && a11y.length < 8) return a11y;
    }
    return nil;
}

static NSString *QDFloatFallbackTitle(NSInteger kind) {
    switch (kind) {
        case 0:  return @"首页";
        case 1:  return @"朋友";
        case 2:  return @"消息";
        case 3:  return @"我";
        default: return nil;
    }
}

// 自绘简约矢量图标：替换 SF Symbols（用户嫌系统图标不好看）。
// 24pt 网格手绘贝塞尔路径，模板渲染由 UITabBar 自动上色；
// 未选中线性描边，选中填充。带缓存：绝对不能每次 tick 都生成新图，
// 否则 selectedImage 反复被替换，返回页面时肉眼可见「卡顿刷新」。
static UIImage *QDFloatIconCached(NSInteger kind, BOOL selected) {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    NSString *key = [NSString stringWithFormat:@"%ld|%d", (long)kind, selected ? 1 : 0];
    UIImage *cached = cache[key];
    if (cached) return cached;

    UIGraphicsImageRendererFormat *fmt = [[UIGraphicsImageRendererFormat alloc] init];
    fmt.scale = [UIScreen mainScreen].scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24) format:fmt];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        // 模板渲染只取 alpha 通道，颜色随意
        UIColor *ink = UIColor.blackColor;
        CGFloat lw = 1.9;
        CGFloat r = 1.15;   // 圆点/圆头半径

        void (^strokePath)(UIBezierPath *) = ^(UIBezierPath *p) {
            p.lineWidth = lw;
            p.lineCapStyle = kCGLineCapRound;
            p.lineJoinStyle = kCGLineJoinRound;
            [ink setStroke];
            [p stroke];
        };

        if (kind == 0) {
            // —— 首页：小房子 ——
            if (selected) {
                UIBezierPath *p = [UIBezierPath bezierPath];
                [p moveToPoint:CGPointMake(3, 11.6)];
                [p addLineToPoint:CGPointMake(12, 3.6)];
                [p addLineToPoint:CGPointMake(21, 11.6)];
                [p addLineToPoint:CGPointMake(19, 11.6)];
                [p addLineToPoint:CGPointMake(19, 20)];
                [p addLineToPoint:CGPointMake(5, 20)];
                [p addLineToPoint:CGPointMake(5, 11.6)];
                [p closePath];
                UIBezierPath *door = [UIBezierPath bezierPathWithRect:CGRectMake(10.2, 14.2, 3.6, 5.8)];
                [p appendPath:door];
                p.usesEvenOddFillRule = YES;
                [ink setFill];
                [p fill];
            } else {
                UIBezierPath *roof = [UIBezierPath bezierPath];
                [roof moveToPoint:CGPointMake(3, 11.6)];
                [roof addLineToPoint:CGPointMake(12, 3.6)];
                [roof addLineToPoint:CGPointMake(21, 11.6)];
                strokePath(roof);
                UIBezierPath *body = [UIBezierPath bezierPath];
                [body moveToPoint:CGPointMake(5.2, 10.2)];
                [body addLineToPoint:CGPointMake(5.2, 20)];
                [body addLineToPoint:CGPointMake(18.8, 20)];
                [body addLineToPoint:CGPointMake(18.8, 10.2)];
                strokePath(body);
                UIBezierPath *door = [UIBezierPath bezierPath];
                [door moveToPoint:CGPointMake(10.2, 20)];
                [door addLineToPoint:CGPointMake(10.2, 14.4)];
                [door addLineToPoint:CGPointMake(13.8, 14.4)];
                [door addLineToPoint:CGPointMake(13.8, 20)];
                strokePath(door);
            }
        } else if (kind == 1) {
            // —— 朋友：两个人 ——
            if (selected) {
                UIBezierPath *p = [UIBezierPath bezierPath];
                [p appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(9.6, 7.6) radius:3.1 startAngle:0 endAngle:M_PI * 2 clockwise:YES]];
                [p appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(16.6, 7.2) radius:2.5 startAngle:0 endAngle:M_PI * 2 clockwise:YES]];
                UIBezierPath *front = [UIBezierPath bezierPath];
                [front moveToPoint:CGPointMake(3.4, 20)];
                [front addCurveToPoint:CGPointMake(15.8, 20) controlPoint1:CGPointMake(3.4, 14.2) controlPoint2:CGPointMake(6.4, 12.4)];
                [p appendPath:front];
                UIBezierPath *back = [UIBezierPath bezierPath];
                [back moveToPoint:CGPointMake(17.4, 12.6)];
                [back addCurveToPoint:CGPointMake(20.6, 20) controlPoint1:CGPointMake(19.6, 13.4) controlPoint2:CGPointMake(20.6, 16.2)];
                [back addLineToPoint:CGPointMake(17.4, 20)];
                [p appendPath:back];
                [ink setFill];
                [p fill];
            } else {
                UIBezierPath *head = [UIBezierPath bezierPathWithArcCenter:CGPointMake(9.6, 7.6) radius:3.1 startAngle:0 endAngle:M_PI * 2 clockwise:YES];
                strokePath(head);
                UIBezierPath *head2 = [UIBezierPath bezierPathWithArcCenter:CGPointMake(16.6, 7.2) radius:2.5 startAngle:0 endAngle:M_PI * 2 clockwise:YES];
                strokePath(head2);
                UIBezierPath *front = [UIBezierPath bezierPath];
                [front moveToPoint:CGPointMake(3.4, 20)];
                [front addCurveToPoint:CGPointMake(15.8, 20) controlPoint1:CGPointMake(3.4, 14.2) controlPoint2:CGPointMake(6.4, 12.4)];
                strokePath(front);
                UIBezierPath *back = [UIBezierPath bezierPath];
                [back moveToPoint:CGPointMake(16.6, 12.2)];
                [back addCurveToPoint:CGPointMake(20.6, 20) controlPoint1:CGPointMake(19.4, 12.8) controlPoint2:CGPointMake(20.6, 15.6)];
                strokePath(back);
            }
        } else if (kind == 2) {
            // —— 消息：对话气泡 + 三个点 ——
            if (selected) {
                UIBezierPath *p = [UIBezierPath bezierPath];
                [p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(3, 4, 18, 13.4) cornerRadius:5.4]];
                UIBezierPath *tail = [UIBezierPath bezierPath];
                [tail moveToPoint:CGPointMake(8.6, 17.2)];
                [tail addLineToPoint:CGPointMake(8.6, 21)];
                [tail addLineToPoint:CGPointMake(13.2, 17.2)];
                [p appendPath:tail];
                for (NSValue *v in @[ [NSValue valueWithCGPoint:CGPointMake(8.4, 10.7)],
                                      [NSValue valueWithCGPoint:CGPointMake(12, 10.7)],
                                      [NSValue valueWithCGPoint:CGPointMake(15.6, 10.7)] ]) {
                    CGPoint c = v.CGPointValue;
                    UIBezierPath *dot = [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:0 endAngle:M_PI * 2 clockwise:YES];
                    [p appendPath:dot];
                }
                p.usesEvenOddFillRule = YES;   // 三个点从实心气泡里镂空出来
                [ink setFill];
                [p fill];
            } else {
                UIBezierPath *bubble = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3, 4, 18, 13.4) cornerRadius:5.4];
                strokePath(bubble);
                UIBezierPath *tail = [UIBezierPath bezierPath];
                [tail moveToPoint:CGPointMake(8.6, 17.4)];
                [tail addLineToPoint:CGPointMake(8.6, 21)];
                [tail addLineToPoint:CGPointMake(13.2, 17.4)];
                strokePath(tail);
                [ink setFill];
                for (NSValue *v in @[ [NSValue valueWithCGPoint:CGPointMake(8.4, 10.7)],
                                      [NSValue valueWithCGPoint:CGPointMake(12, 10.7)],
                                      [NSValue valueWithCGPoint:CGPointMake(15.6, 10.7)] ]) {
                    CGPoint c = v.CGPointValue;
                    UIBezierPath *dot = [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:0 endAngle:M_PI * 2 clockwise:YES];
                    [dot fill];
                }
            }
        } else if (kind == 3) {
            // —— 我：一个人 ——
            if (selected) {
                UIBezierPath *p = [UIBezierPath bezierPath];
                [p appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 7.4) radius:3.7 startAngle:0 endAngle:M_PI * 2 clockwise:YES]];
                UIBezierPath *shoulders = [UIBezierPath bezierPath];
                [shoulders moveToPoint:CGPointMake(4.8, 20.4)];
                [shoulders addCurveToPoint:CGPointMake(19.2, 20.4) controlPoint1:CGPointMake(4.8, 13.8) controlPoint2:CGPointMake(8.2, 12.2)];
                [p appendPath:shoulders];
                [ink setFill];
                [p fill];
            } else {
                UIBezierPath *head = [UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 7.4) radius:3.7 startAngle:0 endAngle:M_PI * 2 clockwise:YES];
                strokePath(head);
                UIBezierPath *shoulders = [UIBezierPath bezierPath];
                [shoulders moveToPoint:CGPointMake(4.8, 20.4)];
                [shoulders addCurveToPoint:CGPointMake(19.2, 20.4) controlPoint1:CGPointMake(4.8, 13.8) controlPoint2:CGPointMake(8.2, 12.2)];
                strokePath(shoulders);
            }
        }
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cache[key] = img;
    return img;
}

// SF Symbols 已被自绘图标替换（QDFloatIconCached）。保留拍摄用的系统加号。
static UIImage *QDFloatIcon(NSInteger kind, BOOL selected) {
    if (kind < 0) return [UIImage systemImageNamed:@"plus"];
    return QDFloatIconCached(kind, selected);
}

// 读抖音按钮当前的角标（只读不建：getter 可能懒建对象，逐帧路径不安全）。
static NSString *QDFloatBadgeValue(id button) {
    if (![button isKindOfClass:[UIView class]]) return nil;
    UIView *badge = nil;
    for (UIView *container in ((UIView *)button).subviews) {
        if (![NSStringFromClass(container.class) isEqualToString:kQDBadgeContainerClass]
            || container.isHidden || container.alpha < 0.01) {
            continue;
        }
        for (UIView *candidate in container.subviews) {
            if ([NSStringFromClass(candidate.class) isEqualToString:kQDBadgeClass]
                && !candidate.isHidden && candidate.alpha >= 0.01
                && !CGRectIsEmpty(candidate.bounds)) {
                badge = candidate;
                break;
            }
        }
        if (badge) break;
    }
    if (!badge) return nil;

    NSString *text = QDYTTKVC(badge, @"badgeText");
    if (text.length > 0) return text;
    unsigned long long count = [QDYTTKVC(badge, @"badgeNumber") unsignedLongLongValue];
    if (count > 0) return @(count).stringValue;
    return @"";   // 有角标但无数字 → 纯红点
}

static void QDFloatSyncBadges(void) {
    if (!gFloatBar || gFloatButtons.count == 0) return;
    NSUInteger count = MIN((NSUInteger)gFloatBar.items.count, gFloatButtons.count);
    for (NSUInteger i = 0; i < count; i++) {
        UITabBarItem *item = gFloatBar.items[i];
        NSString *value = QDFloatBadgeValue(gFloatButtons[i]);
        NSString *current = item.badgeValue;
        if (current != value && ![current isEqualToString:value]) item.badgeValue = value;
    }
}

#pragma mark 悬浮条代理

@interface QDFloatBarProxy : NSObject <UITabBarDelegate>
- (void)plusKeyDidTap;
@end

@implementation QDFloatBarProxy

- (void)plusKeyDidTap {
    // 拍摄不是页面，走抖音自己的拍摄回调，传它自己的按钮。
    UITabBarController *controller = gFloatHost ? QDFloatControllerForView(gFloatHost) : nil;
    if (!controller && gFloatBar) controller = QDFloatControllerForView(gFloatBar);
    SEL selector = NSSelectorFromString(kQDPlusClickSelector);
    id plus = nil;
    for (NSUInteger i = 0; i < gFloatKinds.count; i++) {
        if (gFloatKinds[i].integerValue == -1) { plus = gFloatButtons[i]; break; }
    }
    if (controller && plus && [controller respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, plus);
    }
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    UITabBarController *controller = QDFloatControllerForView(tabBar);
    if (!controller && gFloatHost) controller = QDFloatControllerForView(gFloatHost);
    NSInteger index = (NSInteger)[tabBar.items indexOfObject:item];
    if (!controller || index < 0 || index >= (NSInteger)gFloatButtons.count) return;

    id button = gFloatButtons[(NSUInteger)index];
    if (gFloatKinds[(NSUInteger)index].integerValue == -1) {
        [self plusKeyDidTap];
        // 拍摄不改变选中态，立刻弹回上一个 item。
        UITabBarItem *last = gFloatLastItem;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (last && gFloatBar.selectedItem != last) gFloatBar.selectedItem = last;
        });
        return;
    }

    // 切页必须走抖音自己的按钮点击回调。直接写 selectedIndex 会被它的 override 吞掉。
    // 连手势一并原样回传，抖音据此构造点击上下文，与真实点按走完全相同的路径。
    SEL selector = NSSelectorFromString(kQDTabClickSelector);
    if ([controller respondsToSelector:selector]) {
        id ges = QDYTTKVC(button, @"singleTapGes");
        ((void (*)(id, SEL, id, id))objc_msgSend)(controller, selector, button, ges);
    }
    gFloatLastItem = item;
}

@end

#pragma mark 悬浮条同步

/// 抖音自绘底栏的内容隐去：背景层与按钮 layer.opacity=0、按钮不吃触摸，
/// 交互交给悬浮胶囊。只动 opacity，不动 hidden/alpha——那是抖音的显隐状态，
/// 悬浮条靠继承跟随它（评论区打开时抖音会自己收起底栏，胶囊跟着一起消失）。
static void QDFloatSetContentVisible(AWENormalModeTabBar *bar, NSArray *buttons, BOOL visible) {
    if (!bar) return;
    float opacity = visible ? 1.0f : 0.0f;

    // 底栏自身可能是纯黑实色背景，只隐掉子视图不够 —— 胶囊会压在一块黑底上，
    // 看起来就是「有玻璃但底栏还是黑的」。这里把自背景也清掉，退出时原样还原。
    if (!visible) {
        UIColor *bg = bar.backgroundColor;
        if (bg && CGColorGetAlpha(bg.CGColor) > 0.01) {
            objc_setAssociatedObject(bar, &kQDOrigBGKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            bar.backgroundColor = UIColor.clearColor;
        }
    } else {
        UIColor *orig = objc_getAssociatedObject(bar, &kQDOrigBGKey);
        if (orig) {
            bar.backgroundColor = orig;
            objc_setAssociatedObject(bar, &kQDOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    NSArray *backdrops = @[ QDYTTKVC(bar, @"backgroundView") ?: [NSNull null],
                            QDYTTKVC(bar, @"awe_blurView") ?: [NSNull null],
                            QDYTTKVC(bar, @"separatorLine") ?: [NSNull null],
                            QDYTTKVC(bar, @"skinContainerView") ?: [NSNull null] ];
    for (id backdrop in backdrops) {
        if (![backdrop isKindOfClass:[UIView class]]) continue;
        CALayer *layer = ((UIView *)backdrop).layer;
        if (layer.opacity != opacity) layer.opacity = opacity;
    }
    for (id button in buttons) {
        if (![button isKindOfClass:[UIView class]]) continue;
        UIView *view = (UIView *)button;
        if (view.layer.opacity != opacity) view.layer.opacity = opacity;
        if (view.userInteractionEnabled != visible) view.userInteractionEnabled = visible;
    }
}

static BOOL QDFloatSyncItems(UITabBarController *controller, NSArray *buttons) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSNumber *> *kinds = [NSMutableArray array];
    NSMutableArray *mirrored = [NSMutableArray array];
    NSMutableString *signature = [NSMutableString string];

    for (id button in buttons) {
        UIView *view = [button isKindOfClass:[UIView class]] ? (UIView *)button : nil;
        // 源按钮的 opacity 被本功能置零，不能作为存在性信号；显隐与父视图保留原始语义。
        if (!view || view.isHidden || !view.superview) continue;

        BOOL isPlus = ([QDYTTKVC(button, @"type") longLongValue] == kQDPlusButtonType);

        NSString *title = isPlus ? @"拍摄" : QDFloatButtonTitle(button);
        NSInteger kind = isPlus ? -1 : (NSInteger)[QDYTTKVC(button, @"validIndex") integerValue];
        if (!isPlus && title.length == 0) title = QDFloatFallbackTitle(kind);
        if (title.length == 0) continue;

        [titles addObject:title];
        [kinds addObject:@(kind)];
        [mirrored addObject:button];
        [signature appendFormat:@"%@:%ld|", title, (long)kind];
    }

    if (mirrored.count < 2) return NO;
    // 按钮引用每次都刷新：抖音可能重建出标题相同的新按钮，签名察觉不到，
    // 拿着旧对象转发点击就会落空。
    gFloatButtons = mirrored;

    BOOL rebuilt = ![signature isEqualToString:gFloatSignature];
    if (rebuilt) {
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray arrayWithCapacity:titles.count];
        [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
            NSInteger kind = kinds[index].integerValue;
            UIImage *icon = (kind >= 0) ? QDFloatIcon(kind, NO)
                                        : [UIImage systemImageNamed:@"plus"];
            UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:title image:icon tag:(NSInteger)index];
            [items addObject:item];
        }];
        gFloatBar.items = items;
        gFloatKinds = kinds;
        gFloatSignature = [signature copy];
    }

    // 选中/未选中两套图标（filled / outlined）
    NSInteger selectedKind = (NSInteger)controller.selectedIndex;
    NSUInteger count = MIN((NSUInteger)gFloatBar.items.count, gFloatKinds.count);
    for (NSUInteger i = 0; i < count; i++) {
        UITabBarItem *item = gFloatBar.items[i];
        NSInteger kind = gFloatKinds[i].integerValue;
        if (kind < 0) continue;
        UIImage *sel = QDFloatIcon(kind, YES);
        if (![item.selectedImage isEqual:sel]) item.selectedImage = sel;
    }

    // 选中态跟随抖音（抖音切页可能由别的入口触发，比如推送跳转）
    NSInteger current = -1;
    for (NSUInteger i = 0; i < gFloatKinds.count; i++) {
        if (gFloatKinds[i].integerValue == selectedKind) { current = (NSInteger)i; break; }
    }
    if (current >= 0 && current < (NSInteger)gFloatBar.items.count) {
        UITabBarItem *item = gFloatBar.items[(NSUInteger)current];
        if (gFloatBar.selectedItem != item) {
            gFloatBar.selectedItem = item;
            gFloatLastItem = item;
        }
    }

    QDFloatSyncBadges();
    return rebuilt;
}

/// 读取抖音按钮当前的实色，用于判断宿主明暗。抖音自己换肤，window 的 trait 不一定准，
/// 这里取底栏文字色做锚：白 → 宿主是亮的。
static UIUserInterfaceStyle QDFloatHostStyle(AWENormalModeTabBar *bar, NSArray *buttons) {
    UIWindow *window = bar.window;
    if (window) {
        UIUserInterfaceStyle style = window.windowScene.traitCollection.userInterfaceStyle;
        if (style != UIUserInterfaceStyleUnspecified) return style;
    }
    return UIUserInterfaceStyleDark;   // 抖音默认深色底
}

static void QDFloatTearDown(AWENormalModeTabBar *bar) {
    if (gFloatBar) {
        [gFloatBar removeFromSuperview];
        gFloatBar = nil;
        gFloatProxy = nil;
        gFloatButtons = nil;
        gFloatKinds = nil;
        gFloatSignature = nil;
        gFloatLastItem = nil;
    }
    if (bar) QDFloatSetContentVisible(bar, QDYTTBarButtons(bar), YES);
    gQDFloatActive = NO;
}

static void QDFloatUpdate(AWENormalModeTabBar *bar) {
    // 抖音换过底栏实例时，先把旧实例的内容还原。
    AWENormalModeTabBar *previous = gFloatHost;
    if (previous && previous != bar) {
        QDFloatSetContentVisible(previous, QDYTTBarButtons(previous), YES);
        gFloatSignature = nil;   // 新实例要重建 items
    }
    gFloatHost = bar;

    UITabBarController *controller = QDFloatControllerForView(bar);
    if (!controller) {
        gQDLastFailReason = @"未找到 TabBarController";
        return;
    }

    NSArray *buttons = QDYTTBarButtons(bar);
    if (buttons.count < 2) {
        gQDLastFailReason = @"未找到底栏按钮";
        return;
    }

    if (!gFloatBar) {
        gFloatProxy = [[QDFloatBarProxy alloc] init];
        gFloatBar = [[UITabBar alloc] initWithFrame:bar.bounds];
        gFloatBar.delegate = gFloatProxy;
        gFloatBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        gFloatBar.tintColor = UIColor.labelColor;
        gFloatBar.unselectedItemTintColor = [UIColor colorWithWhite:0 alpha:0.55];

        // 透亮化：只替换胶囊的背景材质为 Clear 档原生玻璃，布局/圆角/动效全部保留。
        // 在保留系统默认 appearance 的基础上改（copy 出来改字段），避免从「系统玻璃」掉回「自定义磨砂」。
        @try {
            Class glassClass = NSClassFromString(@"UIGlassEffect");
            if (glassClass) {
                id effect = nil;
                SEL styleSel = NSSelectorFromString(@"effectWithStyle:");
                if ([glassClass respondsToSelector:styleSel]) {
                    NSInteger style = QDYTTGlassClearEnabled() ? 1 : 0;
                    effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)((id)glassClass, styleSel, style);
                }
                if (!effect) effect = [[glassClass alloc] init];
                if (effect) {
                    UITabBarAppearance *appearance = [gFloatBar.standardAppearance copy] ?: [[UITabBarAppearance alloc] init];
                    appearance.backgroundEffect = effect;
                    appearance.backgroundColor = UIColor.clearColor;
                    appearance.shadowColor = nil;
                    gFloatBar.standardAppearance = appearance;
                    if ([gFloatBar respondsToSelector:@selector(setScrollEdgeAppearance:)]) {
                        gFloatBar.scrollEdgeAppearance = appearance;
                    }
                }
            }
        } @catch (__unused NSException *e) {
        }
        gFloatBar.backgroundColor = UIColor.clearColor;
    }

    // 作为子视图挂在抖音底栏内：显隐/透明度/位置全部随父视图继承。
    if (gFloatBar.superview != bar) [bar addSubview:gFloatBar];
    if (bar.subviews.lastObject != gFloatBar) [bar bringSubviewToFront:gFloatBar];
    if (!CGRectEqualToRect(gFloatBar.frame, bar.bounds)) gFloatBar.frame = bar.bounds;

    // 深浅色：抖音深色皮肤下图标用白，浅色下用黑
    UIUserInterfaceStyle style = QDFloatHostStyle(bar, buttons);
    UIColor *ink = (style == UIUserInterfaceStyleDark) ? UIColor.whiteColor
                                                       : [UIColor colorWithWhite:0 alpha:0.9];
    if (![gFloatBar.tintColor isEqual:ink]) {
        gFloatBar.tintColor = ink;
        gFloatBar.unselectedItemTintColor = (style == UIUserInterfaceStyleDark)
            ? [UIColor colorWithWhite:1 alpha:0.55]
            : [UIColor colorWithWhite:0 alpha:0.55];
    }

    if (QDFloatSyncItems(controller, buttons)) {
        // 重建过 items，让胶囊几何跟着重排一次
        [gFloatBar setNeedsLayout];
    }

    QDFloatSetContentVisible(bar, buttons, NO);
    gQDFloatActive = YES;
    gQDBarGlassApplied = YES;
}

#pragma mark - 主流程

static BOOL QDYTTShouldFloat(void) {
    return QDYTTGlassEnabled() && QDYTTGlassFloatingEnabled() && QDYTTGlassNativeAvailable();
}

static void QDYTTApply(UIView *bar) {
    if (!bar) return;
    NSArray *buttons = QDYTTBarButtons(bar);
    BOOL wantFloat = QDYTTShouldFloat();

    // 引擎切换时把另一套的痕迹清干净
    if (!wantFloat && gQDFloatActive) {
        QDFloatTearDown((AWENormalModeTabBar *)bar);
    }
    if (wantFloat && !gQDFloatActive) {
        QDYTTRestoreVeils(bar);
        QDYTTRemoveOwnGlass(bar);
    }

    if (wantFloat) {
        // 关掉面纱处理：悬浮条盖住全部内容，背景层 opacity 已归零
        QDFloatUpdate((AWENormalModeTabBar *)bar);
        gQDBarGlassApplied = gQDFloatActive;

        if (gQDFloatActive && !gQDToastShown) {
            gQDToastShown = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                [DYYYUtils showToast:@"YTT 悬浮液态玻璃已生效"];
            });
        }
        return;
    }

    // —— 引擎 B：原地换皮 ——
    NSMutableArray<UIVisualEffectView *> *effects = [NSMutableArray array];
    NSMutableArray<UIView *> *plains = [NSMutableArray array];
    QDYTTCollectBackdrops(bar, effects, plains);

    BOOL applied = NO;
    if (QDYTTGlassEnabled()) {
        for (UIVisualEffectView *view in effects) {
            if (QDYTTGlassEffectView(view)) applied = YES;
        }
        if (!applied) {
            // 底栏没有任何现成的毛玻璃层 —— 补一块，并且把压在上面的实色/渐变面纱摘掉，
            // 否则玻璃被盖住，用户看到的还是「一点变化都没有」。
            QDYTTEnsureOwnGlass(bar, buttons);
            applied = YES;
        }
        if (QDYTTGlassGradientEnabled()) {
            QDYTTNeutralizeVeils(bar);
        } else {
            QDYTTRestoreVeils(bar);
        }
        QDYTTUpdateCapsule(bar, buttons);
    } else {
        for (UIVisualEffectView *view in effects) QDYTTUnglassEffectView(view);
        QDYTTRemoveOwnGlass(bar);
        QDYTTRestoreVeils(bar);
        QDYTTUpdateCapsule(bar, buttons);
    }
    gQDBarGlassApplied = applied;

    if (applied && QDYTTGlassEnabled() && !gQDToastShown) {
        gQDToastShown = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYUtils showToast:[NSString stringWithFormat:@"YTT 液态玻璃已生效 · %@", QDYTTGlassEngineName()]];
        });
    }
}

static void QDYTTTick(UIView *hint) {
    if (![NSThread isMainThread]) return;

    // 节流：底栏 layoutSubviews 是逐帧路径，树遍历再便宜也不能每帧做。
    // 0.25s 一次足够跟上切换 tab / 旋转 / 深浅色切换，而且肉眼无感。
    CFTimeInterval now = CACurrentMediaTime();
    if (gQDLastTick > 0 && (now - gQDLastTick) < 0.25) return;
    gQDLastTick = now;
    if (!QDYTTGlassEnabled() && !gQDFloatActive) {
        if (gQDBar) QDYTTApply(gQDBar);
        return;
    }

    UIView *bar = hint;
    if (!bar) {
        bar = gQDBar;
        // 只有已知底栏失效时才做全窗口扫描（贵），平时零扫描。
        if (!bar || bar.window == nil) bar = QDYTTFindBar();
    }
    if (bar) {
        gQDBar = bar;
        gQDBarClassName = NSStringFromClass(bar.class);
        gQDLastFailReason = nil;
        QDYTTApply(bar);
    } else {
        gQDLastFailReason = @"本轮未匹配到底栏";
    }

    static NSUInteger tick = 0;
    tick++;
    if (tick % 12 == 0) QDYTTExtendApply();   // 背景延伸较贵，降频
    if (tick % 4 == 0) QDYTTAutoTintSweep();  // 首页视频全屏播放：底栏颜色跟随视频（1s 一次，成本极低）
}

void QDYTTGlassRefresh(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ QDYTTGlassRefresh(); });
        return;
    }
    gQDLastTick = 0;
    QDYTTTick(gQDBar);
}

#pragma mark - 心跳

@interface QDYTTGlassDriver : NSObject
- (void)heartbeat:(NSTimer *)timer;
@end

@implementation QDYTTGlassDriver

- (void)heartbeat:(__unused NSTimer *)timer {
    @try {
        QDYTTTick(nil);
    } @catch (__unused NSException *exception) {
        // 心跳里绝不抛异常出去，抖音的 runloop 不能被我们带崩
    }
}

@end

static QDYTTGlassDriver *gQDDriver = nil;

static void QDYTTStartHeartbeat(void) {
    if (gQDDriver) return;
    gQDDriver = [[QDYTTGlassDriver alloc] init];
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.2
                                             target:gQDDriver
                                           selector:@selector(heartbeat:)
                                           userInfo:nil
                                            repeats:YES];
    // 必须进 common modes：滚动 / 动画期间 default mode 不跑，返回后玻璃会「晚几秒才回来」。
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

#pragma mark - Hook

%hook AWENormalModeTabBar

- (void)layoutSubviews {
    %orig;
    @try {
        // 返回页面时抖音会把自绘内容重新画出来（opacity 归 1），而 QDYTTTick 有 0.25s
        // 节流，慢半拍就是肉眼可见的「卡顿刷新一下」。这里用已缓存的按钮列表同帧压回，
        // 不做树遍历，开销可忽略。
        if (gQDFloatActive && (id)self == (id)gFloatHost && gFloatButtons.count > 0) {
            QDFloatSetContentVisible(self, gFloatButtons, NO);
        }
        QDYTTTick(self);
    } @catch (__unused NSException *exception) {}
}

%end

// 冷启动时抖音的底栏还没进窗口，先起心跳，等它出现。
%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;
    QDYTTStartHeartbeat();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ QDYTTTick(nil); });
}

%end

// 构造函数的时序不一定早于这些类的注册，所以放在 +load 里，并自己保证幂等。
%ctor {
    QDYTTGlassRegisterDefaults();
    QDYTTStartHeartbeat();
}
