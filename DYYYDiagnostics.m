#import "DYYYDiagnostics.h"
#import "DYYYConstants.h"
#import "DYYYCompatibility.h"
#import "DYYYHookManager.h"
#import "DYYYLogger.h"
#import "DYYYSafetyGuard.h"
#import "DYYYTaskCenter.h"
#import "DYYYUtils.h"
#import <UIKit/UIKit.h>

@implementation DYYYDiagnostics

+ (NSUInteger)enabledFeatureCount {
    NSDictionary *allDefaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSUInteger count = 0;
    for (NSString *key in allDefaults.allKeys) {
        if ([key hasPrefix:@"DYYY"] && [[allDefaults objectForKey:key] isKindOfClass:[NSNumber class]]) {
            count += [(NSNumber *)[allDefaults objectForKey:key] boolValue] ? 1 : 0;
        }
    }
    return count;
}

+ (NSString *)generateReport {
    NSMutableString *report = [NSMutableString string];

    [report appendFormat:@"===== 元抖诊断报告 =====\n"];
    [report appendFormat:@"生成时间：%@\n", [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterLongStyle timeStyle:NSDateFormatterMediumStyle]];
    [report appendFormat:@"插件版本：%@（识别名 %@）\n", DYYY_VERSION, DYYY_NAME];
    [report appendString:@"\n----- 环境 -----\n"];
    NSDictionary<NSString *, NSString *> *env = [DYYYCompatibility environmentInfo];
    for (NSString *key in env) {
        [report appendFormat:@"%@：%@\n", key, env[key]];
    }

    [report appendFormat:@"\n----- 功能 -----\n"];
    [report appendFormat:@"已启用功能数：%lu\n", (unsigned long)[self enabledFeatureCount]];
    [report appendFormat:@"Hook 状态：%@（不兼容 %lu 项）\n", [DYYYHookManager summaryText], (unsigned long)[DYYYHookManager problemCount]];
    [report appendFormat:@"今日完成任务：%lu\n", (unsigned long)[[DYYYTaskCenter shared] finishedCountToday]];
    [report appendFormat:@"运行中任务：%lu\n", (unsigned long)[[DYYYTaskCenter shared] activeTasks].count];

    NSString *lastCrash = [DYYYSafetyGuard lastCrashDescription];
    if (lastCrash.length > 0) {
        [report appendString:@"\n----- 最近崩溃 -----\n"];
        [report appendFormat:@"%@\n", lastCrash];
    }

    NSArray<DYYYHookRecord *> *problems = [[DYYYHookManager allRecords] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == %d OR status == %d", (NSInteger)DYYYHookStatusUnsupported, (NSInteger)DYYYHookStatusFailed]];
    if (problems.count > 0) {
        [report appendString:@"\n----- 不兼容 Hook -----\n"];
        for (DYYYHookRecord *record in problems) {
            [report appendFormat:@"%@ — %@\n", record.hookID, record.detail ?: @"未知原因"];
        }
    }

    NSArray<DYYYLogEntry *> *recentIssues = [DYYYLogger recentWarningsAndErrors];
    if (recentIssues.count > 0) {
        [report appendString:@"\n----- 最近告警（最多 30 条）-----\n"];
        NSUInteger shown = 0;
        for (DYYYLogEntry *entry in recentIssues) {
            if (shown >= 30) {
                break;
            }
            [report appendFormat:@"%@\n", entry.formattedLine];
            shown++;
        }
    } else {
        [report appendString:@"\n----- 最近告警 -----\n(无)\n"];
    }

    [report appendString:@"\n========================\n"];
    return report;
}

+ (NSString *)copyReportToPasteboard {
    NSString *report = [self generateReport];
    [UIPasteboard generalPasteboard].string = report;
    [DYYYLogger info:@"Diagnostics" message:@"诊断报告已复制到剪贴板"];
    return report;
}

+ (void)presentShareSheetForReport {
    NSString *report = [self generateReport];
    NSString *tempPath = [DYYYUtils cachePathForFilename:@"元抖诊断报告.txt"];
    [report writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSURL *fileURL = [NSURL fileURLWithPath:tempPath];
    UIActivityViewController *shareSheet = [[UIActivityViewController alloc] initWithActivityItems:@[ report, fileURL ] applicationActivities:nil];

    UIViewController *topVC = [DYYYUtils topView];
    if (!topVC) {
        return;
    }
    if (shareSheet.popoverPresentationController) {
        shareSheet.popoverPresentationController.sourceView = topVC.view;
        shareSheet.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width / 2.0, topVC.view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    [topVC presentViewController:shareSheet animated:YES completion:nil];
}

@end
