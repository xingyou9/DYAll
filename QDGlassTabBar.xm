//
//  QDGlassTabBar.xm
//  YTT 液态玻璃 — 抖音底栏「原地换皮」
//
//  设计铁律（血泪换来的，改动前请先读）
//  ---------------------------------------------------------------------------
//  1. 只换材质，绝不动布局。
//     找不到现成的毛玻璃层时，才在底栏最底层「补」一块玻璃；frame / 约束 / 层级顺序
//     一律保持抖音原样。所以中间那颗「+」永远在它原来的位置，不会像自建 UITabBar 那样
//     被挤到右边单独成圆。
//
//  2. 材质只用官方 API：[UIGlassEffect effectWithStyle:...]。
//     `[[UIGlassEffect alloc] init]` 不是指定初始化器，可能拿到不可用对象 —— 全程不用它。
//     取不到原生玻璃时退回 UIBlurEffect(systemChromeMaterial)，不会出现「什么都没有」。
//
//  3. 所有写入都必须先比较再写。
//     驱动点是抖音底栏自己的 layoutSubviews，逐帧路径上无脑重写会把抖音的布局环踢起来。
//
//  4. 任何「没做成」都要能看见。
//     首次接管成功弹一次 toast；设置页的状态区直接读 QDYTTGlassBarStatus()。
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
static NSString *const kQDYTTKeyGlass    = @"YTT.glass";
static NSString *const kQDYTTKeyClear    = @"YTT.clear";
static NSString *const kQDYTTKeyGradient = @"YTT.gradient";
static NSString *const kQDYTTKeyCapsule  = @"YTT.capsule";
static NSString *const kQDYTTKeyExtend   = @"YTT.extend";

void QDYTTGlassRegisterDefaults(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            kQDYTTKeyGlass    : @YES,   // 主开关默认开：装上就该看得见
            kQDYTTKeyClear    : @NO,    // Clear 档更通透，但浅色页面对比度会掉，默认关
            kQDYTTKeyGradient : @YES,   // 摘掉压暗玻璃的渐变，是玻璃观感的一部分
            kQDYTTKeyCapsule  : @NO,    // 选中胶囊属于装饰，默认关，避免和抖音自带选中态打架
            kQDYTTKeyExtend   : @NO,    // 背景延伸会改作品图层 frame，默认关
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

#pragma mark - 状态（给设置页读）

static __weak UIView *gQDBar = nil;
static NSString *gQDBarClassName = nil;
static BOOL gQDBarGlassApplied = NO;
static BOOL gQDToastShown = NO;
static NSString *gQDLastFailReason = nil;

// 同样不能依赖编译期 SDK 版本，直接问运行时有没有这个类。
BOOL QDYTTGlassNativeAvailable(void) {
    return NSClassFromString(@"UIGlassEffect") != nil;
}

NSString *QDYTTGlassEngineName(void) {
    return QDYTTGlassNativeAvailable() ? @"原生 UIGlassEffect" : @"降级毛玻璃";
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

#pragma mark - 材质

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
static NSArray *QDYTTBarButtons(UIView *bar) {
    static NSArray<NSString *> *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[ @"tabBarButtons", @"buttons" ];
    });

    for (NSString *key in keys) {
        id value = QDYTTKVC(bar, key);
        if ([value isKindOfClass:[NSArray class]] && [(NSArray *)value count] >= 2) return value;
    }
    id controller = QDYTTKVC(bar, @"yy_viewController");
    for (NSString *key in keys) {
        id value = QDYTTKVC(controller, key);
        if ([value isKindOfClass:[NSArray class]] && [(NSArray *)value count] >= 2) return value;
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
    return found.count >= 2 ? found : nil;
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

#pragma mark - 面纱（压暗玻璃的渐变 / 实色底）处理

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

#pragma mark - 玻璃接管

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

#pragma mark - 选中玻璃胶囊（装饰，默认关闭）

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
        if (@available(iOS 26.0, *)) {
            if ([capsule respondsToSelector:@selector(setCornerConfiguration:)]) {
                Class configClass = NSClassFromString(@"UICornerConfiguration");
                if (configClass && [configClass respondsToSelector:@selector(capsuleConfiguration)]) {
                    capsule.cornerConfiguration = [configClass performSelector:@selector(capsuleConfiguration)];
                }
            }
        }
    }
    if (capsule.layer.cornerRadius != radius) {
        capsule.layer.cornerRadius = radius;
        capsule.clipsToBounds = YES;
    }
}

#pragma mark - 背景延伸（作品图层铺到屏幕底部，消除灰底 / 色差）

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
    if (windowBounds.size.width < windowBounds.size.height) return;   // 只处理竖屏

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

#pragma mark - 主流程

static void QDYTTApply(UIView *bar) {
    if (!bar) return;
    NSArray *buttons = QDYTTBarButtons(bar);

    if (!QDYTTGlassEnabled()) {
        NSMutableArray<UIVisualEffectView *> *effects = [NSMutableArray array];
        NSMutableArray<UIView *> *plains = [NSMutableArray array];
        QDYTTCollectBackdrops(bar, effects, plains);
        for (UIVisualEffectView *view in effects) QDYTTUnglassEffectView(view);
        QDYTTRemoveOwnGlass(bar);
        QDYTTRestoreVeils(bar);
        QDYTTUpdateCapsule(bar, buttons);
        gQDBarGlassApplied = NO;
        return;
    }

    NSMutableArray<UIVisualEffectView *> *effects = [NSMutableArray array];
    NSMutableArray<UIView *> *plains = [NSMutableArray array];
    QDYTTCollectBackdrops(bar, effects, plains);

    BOOL applied = NO;
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
    gQDBarGlassApplied = applied;

    if (applied && !gQDToastShown) {
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
    static CFTimeInterval gQDLastTick = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (gQDLastTick > 0 && (now - gQDLastTick) < 0.25) return;
    gQDLastTick = now;
    if (!QDYTTGlassEnabled() && !QDYTTGlassExtendEnabled()) {
        if (gQDBar) QDYTTApply(gQDBar);
        return;
    }

    UIView *bar = hint;
    if (!bar) {
        bar = gQDBar;
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
}

void QDYTTGlassRefresh(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ QDYTTGlassRefresh(); });
        return;
    }
    QDYTTTick(nil);
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
