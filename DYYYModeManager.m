// DYYYModeManager.m — 模式系统实现
#import "DYYYModeManager.h"

NSString * const DYYYModeDidChangeNotification = @"DYYYModeDidChangeNotification";
static NSString * const kDYYYCurrentModeKey = @"DYYY.CurrentMode";

@implementation DYYYModeManager

+ (instancetype)shared {
    static DYYYModeManager *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[DYYYModeManager alloc] init]; });
    return inst;
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)allModes {
    return @[
        @{ @"id" : @"standard",   @"name" : @"标准模式",   @"subtitle" : @"默认体验，全部功能保持你自己的开关" },
        @{ @"id" : @"clean",      @"name" : @"清爽模式",   @"subtitle" : @"隐藏弹幕按钮 / 搜索气泡 / 红点等界面杂物" },
        @{ @"id" : @"immersive",  @"name" : @"沉浸模式",   @"subtitle" : @"全屏播放 + 液态玻璃 + 底栏颜色跟随视频" },
        @{ @"id" : @"performance",@"name" : @"性能模式",   @"subtitle" : @"关闭玻璃特效 / 悬浮按钮 / 评论区模糊，优先流畅" },
        @{ @"id" : @"battery",    @"name" : @"省电模式",   @"subtitle" : @"在性能模式基础上关闭全部玻璃渲染" },
        @{ @"id" : @"custom",     @"name" : @"自定义模式", @"subtitle" : @"不批量改动，保留当前所有开关" },
    ];
}

- (NSString *)currentModeID {
    NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:kDYYYCurrentModeKey];
    return v.length ? v : @"standard";
}

- (NSString *)subtitleForMode:(NSString *)modeID {
    for (NSDictionary *m in [self allModes]) {
        if ([m[@"id"] isEqualToString:modeID]) return m[@"subtitle"];
    }
    return @"";
}

- (NSUInteger)applyMode:(NSString *)modeID {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary<NSString *, NSNumber *> *changes = nil;
    if ([modeID isEqualToString:@"clean"]) {
        changes = @{
            @"DYYYHideDanmuButton"  : @YES,
            @"DYYYHideSearchBubble" : @YES,
            @"DYYYHideBottomDot"    : @YES,
            @"DYYYHideAvatarBubble" : @YES,
        };
    } else if ([modeID isEqualToString:@"immersive"]) {
        changes = @{
            @"DYYYisEnableFullScreen" : @YES,
            @"YTT.glass"              : @YES,
            @"YTT.extend"             : @YES,
            @"YTT.autotint"           : @YES,
            @"YTT.clear"              : @YES,
        };
    } else if ([modeID isEqualToString:@"performance"]) {
        changes = @{
            @"DYYYEnableFloatSpeedButton" : @NO,
            @"DYYYEnableFloatClearButton" : @NO,
            @"DYYYisEnableCommentBlur"    : @NO,
            @"YTT.autotint"               : @NO,
            @"YTT.extend"                 : @NO,
            @"YTT.clear"                  : @NO,
            @"YTT.glass"                  : @YES,   // 保留玻璃但关闭重特效
        };
    } else if ([modeID isEqualToString:@"battery"]) {
        changes = @{
            @"DYYYEnableFloatSpeedButton" : @NO,
            @"DYYYEnableFloatClearButton" : @NO,
            @"DYYYisEnableCommentBlur"    : @NO,
            @"YTT.autotint"               : @NO,
            @"YTT.extend"                 : @NO,
            @"YTT.clear"                  : @NO,
            @"YTT.glass"                  : @NO,
        };
    } else if ([modeID isEqualToString:@"custom"]) {
        [defs setObject:modeID forKey:kDYYYCurrentModeKey];
        [defs synchronize];
        return 0;
    } else {
        // standard：恢复性能相关项为默认轻量状态，其他键不动（用户自管）
        changes = @{ @"YTT.autotint" : @YES, @"YTT.extend" : @YES };
    }
    if (!changes) return 0;

    // 依赖处理：开启 YTT 子功能时确保 YTT.glass 开启（省电/性能模式除外，那里显式控制）
    BOOL glassExplicit = [modeID isEqualToString:@"battery"] || [modeID isEqualToString:@"performance"];
    if (!glassExplicit) {
        BOOL anyGlassChild = changes[@"YTT.clear"] == [NSNumber numberWithBool:YES]
                          || changes[@"YTT.extend"] == [NSNumber numberWithBool:YES]
                          || changes[@"YTT.autotint"] == [NSNumber numberWithBool:YES];
        if (anyGlassChild) {
            [defs setBool:YES forKey:@"YTT.glass"];
        }
    }

    for (NSString *k in changes.allKeys) {
        [defs setBool:[changes[k] boolValue] forKey:k];
    }
    [defs setObject:modeID forKey:kDYYYCurrentModeKey];
    [defs synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:DYYYModeDidChangeNotification object:modeID];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DYYYGlobalTransparencyDidChangeNotification" object:nil];
    return changes.count;
}

@end
