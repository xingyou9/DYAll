#import "DYYYHookManager.h"
#import "DYYYLogger.h"
#import <objc/runtime.h>

@implementation DYYYHookRecord
@end

@interface DYYYHookManager ()
@property(nonatomic, strong) NSMutableArray<DYYYHookRecord *> *records;
@property(nonatomic, strong) dispatch_queue_t queue;
@end

@implementation DYYYHookManager

+ (instancetype)shared {
    static DYYYHookManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _records = [NSMutableArray array];
        _queue = dispatch_queue_create("com.dyyy.hookmanager.queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (BOOL)checkClass:(NSString *)className selector:(NSString *)selectorName hookID:(NSString *)hookID {
    Class cls = className ? objc_getClass(className.UTF8String) : Nil;
    if (!cls) {
        [self recordHookWithID:hookID className:className selectorName:selectorName status:DYYYHookStatusUnsupported detail:@"目标类不存在（抖音版本可能已更新）"];
        return NO;
    }
    if (selectorName.length > 0) {
        SEL sel = NSSelectorFromString(selectorName);
        if (!class_getInstanceMethod(cls, sel) && !class_getClassMethod(cls, sel)) {
            [self recordHookWithID:hookID className:className selectorName:selectorName status:DYYYHookStatusUnsupported detail:@"目标方法不存在（抖音版本可能已更新）"];
            return NO;
        }
    }
    [self recordHookWithID:hookID className:className selectorName:selectorName status:DYYYHookStatusSupported detail:nil];
    return YES;
}

+ (BOOL)checkClass:(NSString *)className hookID:(NSString *)hookID {
    return [self checkClass:className selector:nil hookID:hookID];
}

+ (void)recordHookWithID:(NSString *)hookID
            className:(NSString *)className
         selectorName:(NSString *)selectorName
               status:(DYYYHookStatus)status
               detail:(NSString *)detail {
    if (!hookID.length) {
        return;
    }
    dispatch_barrier_async([self shared].queue, ^{
      // 同一 hookID 重复登记时覆盖旧记录，保留最新状态
      NSMutableArray *toRemove = [NSMutableArray array];
      for (DYYYHookRecord *existing in [self shared].records) {
          if ([existing.hookID isEqualToString:hookID]) {
              [toRemove addObject:existing];
          }
      }
      [[self shared].records removeObjectsInArray:toRemove];

      DYYYHookRecord *record = [[DYYYHookRecord alloc] init];
      record.hookID = hookID;
      record.className = className;
      record.selectorName = selectorName;
      record.status = status;
      record.detail = detail;
      record.recordedAt = [NSDate date];
      [[self shared].records addObject:record];

      if (status == DYYYHookStatusUnsupported || status == DYYYHookStatusFailed) {
          [DYYYLogger warning:@"HookGuard" message:[NSString stringWithFormat:@"[%@] %@ %@ %@", hookID, className ?: @"", selectorName ?: @"", detail ?: @""]];
      } else if ([DYYYLogger verboseEnabled]) {
          [DYYYLogger debug:@"HookGuard" message:[NSString stringWithFormat:@"[%@] OK", hookID]];
      }
    });
}

+ (NSArray<DYYYHookRecord *> *)allRecords {
    __block NSArray<DYYYHookRecord *> *result;
    dispatch_sync([self shared].queue, ^{
      result = [[self shared].records copy];
    });
    return result ?: @[];
}

+ (NSUInteger)problemCount {
    __block NSUInteger count = 0;
    dispatch_sync([self shared].queue, ^{
      for (DYYYHookRecord *record in [self shared].records) {
          if (record.status == DYYYHookStatusUnsupported || record.status == DYYYHookStatusFailed) {
              count++;
          }
      }
    });
    return count;
}

+ (NSString *)summaryText {
    NSUInteger total = [self allRecords].count;
    NSUInteger problems = [self problemCount];
    if (total == 0) {
        return @"未登记";
    }
    return [NSString stringWithFormat:@"%lu 正常 / %lu 异常", (unsigned long)(total - problems), (unsigned long)problems];
}

+ (NSString *)reportString {
    NSMutableString *text = [NSMutableString string];
    NSArray<DYYYHookRecord *> *records = [self allRecords];
    if (records.count == 0) {
        return @"(尚无 Hook 登记记录)";
    }
    [text appendString:@"Hook 状态明细：\n"];
    for (DYYYHookRecord *record in records) {
        NSString *statusText;
        switch (record.status) {
            case DYYYHookStatusSupported:   statusText = @"✓ 生效"; break;
            case DYYYHookStatusUnsupported: statusText = @"⚠ 不兼容"; break;
            case DYYYHookStatusDisabled:    statusText = @"- 已关闭"; break;
            case DYYYHookStatusFailed:      statusText = @"✗ 失败"; break;
        }
        [text appendFormat:@"  %@  %@", statusText, record.hookID];
        if (record.className.length > 0) {
            [text appendFormat:@"  (%@", record.className];
            if (record.selectorName.length > 0) {
                [text appendFormat:@" %@", record.selectorName];
            }
            [text appendString:@")"];
        }
        if (record.detail.length > 0) {
            [text appendFormat:@"  — %@", record.detail];
        }
        [text appendString:@"\n"];
    }
    return text;
}

+ (void)reset {
    dispatch_barrier_async([self shared].queue, ^{
      [[self shared].records removeAllObjects];
    });
}

@end
