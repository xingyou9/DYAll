#import "DYYYCompatibility.h"
#import "DYYYConstants.h"
#import "DYYYHookManager.h"
#import "DYYYLogger.h"
#import "DYYYSafetyGuard.h"
#import "DYYYUtils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

@implementation DYYYCompatibility

+ (NSString *)iOSVersion {
    return [UIDevice currentDevice].systemVersion;
}

+ (NSString *)deviceModel {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size == 0) {
        return @"未知";
    }
    char *machine = malloc(size);
    if (!machine) {
        return @"未知";
    }
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *result = [NSString stringWithUTF8String:machine] ?: @"未知";
    free(machine);
    return result;
}

+ (NSString *)architectureName {
#if defined(__arm64e__)
    return @"arm64e（fat 二进制，运行时以系统裁决为准）";
#elif defined(__aarch64__) || defined(__arm64__)
    return @"arm64（fat 二进制，运行时以系统裁决为准）";
#else
    return @"未知";
#endif
}

+ (NSString *)douyinVersion {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";
}

+ (NSString *)douyinBuild {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey] ?: @"未知";
}

+ (NSString *)jailbreakScheme {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/var/jb/var/jb"]) {
        return @"RootHide";
    }
    if ([fm fileExistsAtPath:@"/var/jb"]) {
        return @"Rootless (Dopamine/palera1n)";
    }
    if ([fm fileExistsAtPath:@"/Library/MobileSubstrate/MobileSubstrate.dylib"]) {
        return @"Rootful";
    }
    return @"未知";
}

+ (NSString *)testedDouyinVersion {
    return @"36.5.0";
}

+ (NSString *)douyinCompatibilityStatus {
    NSString *current = [self douyinVersion];
    if ([current isEqualToString:@"未知"]) {
        return @"未知";
    }
    NSComparisonResult result = [DYYYUtils compareVersion:current toVersion:[self testedDouyinVersion]];
    switch (result) {
        case NSOrderedAscending:
        case NSOrderedSame:
            return @"已验证";
        case NSOrderedDescending:
            return @"未验证（抖音版本较新）";
    }
    return @"未知";
}

+ (BOOL)glassEffectSupported {
    if ([self iOSVersionDouble] < 26.0) {
        return NO;
    }
    return NSClassFromString(@"UIGlassEffect") != nil;
}

+ (double)iOSVersionDouble {
    return [self iOSVersion].doubleValue;
}

+ (NSDictionary<NSString *, NSString *> *)environmentInfo {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"iOS 版本"] = [self iOSVersion];
    info[@"设备型号"] = [self deviceModel];
    info[@"抖音版本"] = [NSString stringWithFormat:@"%@ (%@)", [self douyinVersion], [self douyinBuild]];
    info[@"抖音兼容性"] = [self douyinCompatibilityStatus];
    info[@"运行模式"] = [self jailbreakScheme];
    info[@"液态玻璃"] = [self glassEffectSupported] ? @"支持" : @"不支持（自动回退毛玻璃）";
    info[@"安全模式"] = [DYYYSafetyGuard isSafeMode] ? @"已开启" : @"未开启";
    info[@"崩溃计数"] = [NSString stringWithFormat:@"%lu", (unsigned long)[DYYYSafetyGuard consecutiveCrashCount]];
    return info;
}

+ (void)performStartupChecks {
    @try {
        [DYYYLogger info:@"Compat" message:[NSString stringWithFormat:@"环境：iOS %@ / %@ / %@ / 抖音 %@ / %@", [self iOSVersion], [self deviceModel], [self jailbreakScheme], [self douyinVersion], [self douyinCompatibilityStatus]]];

        // 设置页关键依赖类检查 —— 缺失时设置入口无法工作，提前记录并在状态中心展示
        NSArray<NSDictionary *> *requiredClasses = @[
            @{ @"name" : @"AWESettingBaseViewController", @"id" : @"依赖.设置页控制器" },
            @{ @"name" : @"AWESettingsViewModel", @"id" : @"依赖.设置页模型" },
            @{ @"name" : @"AWESettingItemModel", @"id" : @"依赖.设置项模型" },
            @{ @"name" : @"AWESettingSectionModel", @"id" : @"依赖.设置分组模型" },
        ];
        for (NSDictionary *entry in requiredClasses) {
            [DYYYHookManager checkClass:entry[@"name"] hookID:entry[@"id"]];
        }

        // 能力探测（只登记，不阻断）
        [DYYYHookManager recordHookWithID:@"能力.液态玻璃"
                             className:@"UIGlassEffect"
                           selectorName:nil
                                 status:[self glassEffectSupported] ? DYYYHookStatusSupported : DYYYHookStatusUnsupported
                                 detail:[self glassEffectSupported] ? nil : @"需要 iOS 26+，已自动回退毛玻璃"];

        if (![[self douyinCompatibilityStatus] isEqualToString:@"已验证"]) {
            [DYYYLogger warning:@"Compat" message:[NSString stringWithFormat:@"当前抖音 %@ 超出已验证版本 %@，部分 Hook 可能失效；失效项将在状态中心列出", [self douyinVersion], [self testedDouyinVersion]]];
        }
    } @catch (NSException *exception) {
        // 兼容性检查绝不能让启动崩溃
        [DYYYLogger logException:exception module:@"Compat"];
    }
}

+ (BOOL)glassUIEnabled {
    if ([DYYYSafetyGuard isSafeMode]) {
        return NO;
    }
    return ![[NSUserDefaults standardUserDefaults] boolForKey:@"DYAllGlassUIDisabled"];
}

+ (BOOL)dependencyCheckPassed {
    for (DYYYHookRecord *record in [DYYYHookManager allRecords]) {
        if ([record.hookID hasPrefix:@"依赖."] && record.status == DYYYHookStatusUnsupported) {
            return NO;
        }
    }
    return YES;
}

@end
