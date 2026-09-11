// DYYYFeatureRegistry.m — 统一功能注册表实现
#import "DYYYFeatureRegistry.h"
#import <objc/runtime.h>

NSString * const DYYYFeatureDidChangeNotification = @"DYYYFeatureDidChangeNotification";

// 构造期可写
@interface DYYYFeatureDescriptor ()
@property (nonatomic, copy, readwrite) NSString *featureID;
@property (nonatomic, copy, readwrite) NSString *displayName;
@property (nonatomic, copy, readwrite) NSString *category;
@property (nonatomic, copy, readwrite) NSString *prefKey;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *dependencies;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *conflicts;
@property (nonatomic, copy, readwrite) NSString *minAppVersion;
@property (nonatomic, copy, readwrite) NSString *maxAppVersion;
@property (nonatomic, assign, readwrite) DYYYFeatureRisk riskLevel;
@end

@implementation DYYYFeatureDescriptor
@end

@interface DYYYFeatureRegistry ()
@property (nonatomic, strong) NSMutableArray<DYYYFeatureDescriptor *> *features;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *recentUse; // prefKey -> date
@end

@implementation DYYYFeatureRegistry

+ (instancetype)shared {
    static DYYYFeatureRegistry *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[DYYYFeatureRegistry alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _features = [NSMutableArray array];
        _recentUse = [NSMutableDictionary dictionary];
        [self registerBuiltins];
    }
    return self;
}

- (DYYYFeatureDescriptor *)addFeature:(NSString *)fid
                                 name:(NSString *)name
                             category:(NSString *)category
                              prefKey:(NSString *)key
                                 deps:(NSArray<NSString *> *)deps
                            conflicts:(NSArray<NSString *> *)conflicts
                              risk:(DYYYFeatureRisk)risk {
    DYYYFeatureDescriptor *d = [[DYYYFeatureDescriptor alloc] init];
    d.featureID = fid;
    d.displayName = name;
    d.category = category;
    d.prefKey = key;
    d.dependencies = deps ?: @[];
    d.conflicts = conflicts ?: @[];
    d.minAppVersion = @"36.5.0";
    d.maxAppVersion = @"";
    d.riskLevel = risk;
    [self.features addObject:d];
    return d;
}

- (void)registerBuiltins {
    // 仅收录实测存在的偏好键；依赖/冲突均为真实语义
    [self addFeature:@"noads"             name:@"无广告模式"         category:@"基本"  prefKey:@"DYYYNoAds"                    deps:@[]        conflicts:@[]               risk:DYYYFeatureRiskLow];
    [self addFeature:@"fullscreen"        name:@"全屏播放"           category:@"视频"  prefKey:@"DYYYisEnableFullScreen"       deps:@[]        conflicts:@[]               risk:DYYYFeatureRiskLow];
    [self addFeature:@"copytext"          name:@"长按复制文案"       category:@"基本"  prefKey:@"DYYYLongPressCopyTextEnabled" deps:@[]        conflicts:@[]               risk:DYYYFeatureRiskLow];
    [self addFeature:@"commentblur"       name:@"评论区模糊"         category:@"界面"  prefKey:@"DYYYisEnableCommentBlur"      deps:@[]        conflicts:@[@"hidecomment"] risk:DYYYFeatureRiskMedium];
    [self addFeature:@"hidecomment"       name:@"隐藏评论区"         category:@"隐藏"  prefKey:@"DYYYHideComment"              deps:@[]        conflicts:@[@"commentblur"] risk:DYYYFeatureRiskLow];
    [self addFeature:@"floatspeed"        name:@"悬浮倍速按钮"       category:@"悬浮"  prefKey:@"DYYYEnableFloatSpeedButton"   deps:@[]        conflicts:@[]               risk:DYYYFeatureRiskLow];
    [self addFeature:@"floatclear"        name:@"悬浮清屏按钮"       category:@"悬浮"  prefKey:@"DYYYEnableFloatClearButton"   deps:@[]        conflicts:@[]               risk:DYYYFeatureRiskLow];
    [self addFeature:@"hidedanmu"         name:@"隐藏弹幕按钮"       category:@"隐藏"  prefKey:@"DYYYHideDanmuButton"          deps:@[]        conflicts:@[]               risk:DYYYFeatureRiskLow];
    [self addFeature:@"hidesearch"        name:@"隐藏搜索气泡"       category:@"隐藏"  prefKey:@"DYYYHideSearchBubble"         deps:@[]        conflicts:@[]               risk:DYYYFeatureRiskLow];
    [self addFeature:@"blockisland"       name:@"屏蔽灵动岛"         category:@"隐私"  prefKey:@"DYYYBlockDynamicIsland"       deps:@[]        conflicts:@[]               risk:DYYYFeatureRiskLow];
    [self addFeature:@"glass"             name:@"YTT 液态玻璃"       category:@"界面"  prefKey:@"YTT.glass"                    deps:@[]        conflicts:@[]               risk:DYYYFeatureRiskMedium];
    [self addFeature:@"glasstransparent"  name:@"玻璃透亮档"         category:@"界面"  prefKey:@"YTT.clear"                    deps:@[@"glass"] conflicts:@[]              risk:DYYYFeatureRiskLow];
    [self addFeature:@"glasstint"         name:@"底栏颜色跟随视频"   category:@"界面"  prefKey:@"YTT.autotint"                 deps:@[@"glass"] conflicts:@[]              risk:DYYYFeatureRiskMedium];
    [self addFeature:@"glassextend"       name:@"视频透出底栏"       category:@"界面"  prefKey:@"YTT.extend"                   deps:@[@"glass"] conflicts:@[]              risk:DYYYFeatureRiskMedium];
}

- (NSArray<DYYYFeatureDescriptor *> *)allFeatures {
    return [self.features copy];
}

- (DYYYFeatureDescriptor *)featureForPrefKey:(NSString *)key {
    if (key.length == 0) return nil;
    for (DYYYFeatureDescriptor *f in self.features) {
        if ([f.prefKey isEqualToString:key]) return f;
    }
    return nil;
}

- (DYYYFeatureDescriptor *)featureForID:(NSString *)featureID {
    for (DYYYFeatureDescriptor *f in self.features) {
        if ([f.featureID isEqualToString:featureID]) return f;
    }
    return nil;
}

- (BOOL)isEnabledForFeature:(DYYYFeatureDescriptor *)feature {
    if (!feature.prefKey.length) return NO;
    return [[NSUserDefaults standardUserDefaults] boolForKey:feature.prefKey];
}

- (NSArray<NSString *> *)conflictNamesIfEnabling:(DYYYFeatureDescriptor *)feature {
    if (!feature) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *cid in feature.conflicts) {
        DYYYFeatureDescriptor *other = [self featureForID:cid];
        if (other && [self isEnabledForFeature:other]) {
            [out addObject:other.displayName];
        }
    }
    // 反向：别人声明了与本功能冲突
    for (DYYYFeatureDescriptor *other in self.features) {
        if ([other.featureID isEqualToString:feature.featureID]) continue;
        if ([other.conflicts containsObject:feature.featureID] && [self isEnabledForFeature:other]) {
            [out addObject:other.displayName];
        }
    }
    return [out copy];
}

- (NSArray<NSString *> *)unmetDependencyNamesIfEnabling:(DYYYFeatureDescriptor *)feature {
    if (!feature) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *did in feature.dependencies) {
        DYYYFeatureDescriptor *dep = [self featureForID:did];
        if (dep && ![self isEnabledForFeature:dep]) {
            [out addObject:dep.displayName];
        }
    }
    return [out copy];
}

- (void)setEnabled:(BOOL)enabled forFeature:(DYYYFeatureDescriptor *)feature {
    if (!feature.prefKey.length) return;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setBool:enabled forKey:feature.prefKey];
    [defs synchronize];
    if (enabled) {
        // 自动满足依赖
        for (NSString *did in feature.dependencies) {
            DYYYFeatureDescriptor *dep = [self featureForID:did];
            if (dep && ![self isEnabledForFeature:dep]) {
                [defs setBool:YES forKey:dep.prefKey];
            }
        }
    } else {
        // 关闭被依赖方时自动关闭依赖它的功能，避免悬空依赖
        for (DYYYFeatureDescriptor *other in self.features) {
            if ([other.dependencies containsObject:feature.featureID] && [self isEnabledForFeature:other]) {
                [defs setBool:NO forKey:other.prefKey];
            }
        }
    }
    [defs synchronize];
    [self recordUseOfPrefKey:feature.prefKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:DYYYFeatureDidChangeNotification
                                                        object:feature.prefKey];
}

#pragma mark 最近使用

- (void)recordUseOfPrefKey:(NSString *)key {
    if (key.length == 0) return;
    self.recentUse[key] = [NSDate date];
    // 只保留 20 条，防无限增长
    if (self.recentUse.count > 20) {
        NSArray<NSString *> *sorted = [self.recentUse keysSortedByValueUsingComparator:^NSComparisonResult(NSDate *a, NSDate *b) {
            return [b compare:a];
        }];
        for (NSUInteger i = 20; i < sorted.count; i++) {
            [self.recentUse removeObjectForKey:sorted[i]];
        }
    }
}

- (NSArray<NSString *> *)recentlyUsedNames:(NSUInteger)maxCount {
    NSArray<NSString *> *keys = [self.recentUse keysSortedByValueUsingComparator:^NSComparisonResult(NSDate *a, NSDate *b) {
        return [b compare:a];
    }];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *k in keys) {
        if (names.count >= maxCount) break;
        DYYYFeatureDescriptor *f = [self featureForPrefKey:k];
        [names addObject:f ? f.displayName : k];
    }
    return [names copy];
}

+ (NSString *)riskTextForLevel:(DYYYFeatureRisk)level {
    switch (level) {
        case DYYYFeatureRiskLow:    return @"低";
        case DYYYFeatureRiskMedium: return @"中";
        case DYYYFeatureRiskHigh:   return @"高";
    }
    return @"低";
}

@end
