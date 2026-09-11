#import "DYYYTaskCenter.h"
#import "DYYYLogger.h"

NSString *DYYYTaskStateName(DYYYTaskState state) {
    switch (state) {
        case DYYYTaskStateRunning:   return @"运行中";
        case DYYYTaskStateDone:      return @"已完成";
        case DYYYTaskStateFailed:    return @"失败";
        case DYYYTaskStateCancelled: return @"已取消";
    }
    return @"未知";
}

static const NSUInteger kDYYYHistoryLimit = 100;

static NSString *DYYYHistoryFilePath(void) {
    NSString *library = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    return [library stringByAppendingPathComponent:@"元抖/task_history.plist"];
}

@implementation DYYYTaskRecord

- (BOOL)isActive {
    return _state == DYYYTaskStateRunning;
}

- (NSDictionary *)dictionaryRepresentation {
    // 注意：NSNull 不是合法 plist 类型，finishedAt 为空时必须省略键，否则 writeToFile 会静默失败
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"taskID"] = _taskID ?: @"";
    dict[@"title"] = _title ?: @"";
    dict[@"type"] = _type ?: @"";
    dict[@"state"] = @(_state);
    dict[@"progress"] = @(_progress);
    dict[@"createdAt"] = _createdAt ?: [NSDate date];
    if (_finishedAt) {
        dict[@"finishedAt"] = _finishedAt;
    }
    dict[@"fileURL"] = _fileURL ?: @"";
    dict[@"detail"] = _detail ?: @"";
    return dict;
}

+ (instancetype)recordFromDictionary:(NSDictionary *)dict {
    DYYYTaskRecord *record = [[self alloc] init];
    record.taskID = [dict objectForKey:@"taskID"] ?: @"";
    record.title = [dict objectForKey:@"title"] ?: @"未命名任务";
    record.type = [dict objectForKey:@"type"] ?: @"";
    record.state = [[dict objectForKey:@"state"] isKindOfClass:[NSNumber class]] ? [[dict objectForKey:@"state"] integerValue] : DYYYTaskStateDone;
    record.progress = [[dict objectForKey:@"progress"] isKindOfClass:[NSNumber class]] ? [[dict objectForKey:@"progress"] floatValue] : 0.0f;
    record.createdAt = [dict objectForKey:@"createdAt"] ?: [NSDate date];
    id finishedAt = [dict objectForKey:@"finishedAt"];
    record.finishedAt = [finishedAt isKindOfClass:[NSDate class]] ? finishedAt : nil;
    NSString *fileURL = [dict objectForKey:@"fileURL"];
    record.fileURL = [fileURL isKindOfClass:[NSString class]] && fileURL.length > 0 ? fileURL : nil;
    record.detail = [dict objectForKey:@"detail"];
    return record;
}

@end

@interface DYYYTaskCenter ()
@property(nonatomic, strong) NSMutableDictionary<NSString *, DYYYTaskRecord *> *activeRecords;
@property(nonatomic, strong) NSMutableArray<DYYYTaskRecord *> *historyRecords;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, assign) BOOL historyLoaded;
@end

@implementation DYYYTaskCenter

+ (instancetype)shared {
    static DYYYTaskCenter *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _activeRecords = [NSMutableDictionary dictionary];
        _historyRecords = [NSMutableArray array];
        _queue = dispatch_queue_create("com.dyyy.taskcenter.queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)reloadHistoryIfNeeded {
    if (self.historyLoaded) {
        return;
    }
    dispatch_sync(self.queue, ^{
      if (self.historyLoaded) {
          return;
      }
      NSArray *stored = [NSArray arrayWithContentsOfFile:DYYYHistoryFilePath()];
      for (NSDictionary *dict in stored) {
          if ([dict isKindOfClass:[NSDictionary class]]) {
              DYYYTaskRecord *record = [DYYYTaskRecord recordFromDictionary:dict];
              if (record) {
                  [self.historyRecords addObject:record];
              }
          }
      }
      self.historyLoaded = YES;
    });
}

- (void)beginTaskWithID:(NSString *)taskID title:(NSString *)title type:(NSString *)type {
    if (taskID.length == 0) {
        return;
    }
    dispatch_barrier_async(self.queue, ^{
      if (self.activeRecords[taskID]) {
          return;
      }
      DYYYTaskRecord *record = [[DYYYTaskRecord alloc] init];
      record.taskID = taskID;
      record.title = title ?: @"未命名任务";
      record.type = type ?: @"";
      record.state = DYYYTaskStateRunning;
      record.progress = 0.0f;
      record.createdAt = [NSDate date];
      self.activeRecords[taskID] = record;

      [DYYYLogger debug:@"TaskCenter" message:[NSString stringWithFormat:@"任务开始 [%@] %@", type ?: @"", title ?: @""]];
    });
}

- (void)updateProgress:(float)progress forTaskID:(NSString *)taskID {
    if (taskID.length == 0) {
        return;
    }
    dispatch_barrier_async(self.queue, ^{
      DYYYTaskRecord *record = self.activeRecords[taskID];
      if (record) {
          record.progress = MIN(MAX(progress, 0.0f), 1.0f);
      }
    });
}

- (void)setDetail:(NSString *)detail forTaskID:(NSString *)taskID {
    if (taskID.length == 0) {
        return;
    }
    dispatch_barrier_async(self.queue, ^{
      DYYYTaskRecord *record = self.activeRecords[taskID];
      if (record) {
          record.detail = detail;
      }
    });
}

- (void)finishTaskWithID:(NSString *)taskID success:(BOOL)success cancelled:(BOOL)cancelled fileURL:(NSURL *)fileURL {
    if (taskID.length == 0) {
        return;
    }
    dispatch_barrier_async(self.queue, ^{
      DYYYTaskRecord *record = self.activeRecords[taskID];
      [self.activeRecords removeObjectForKey:taskID];
      if (!record) {
          return;
      }

      if (cancelled) {
          record.state = DYYYTaskStateCancelled;
      } else {
          record.state = success ? DYYYTaskStateDone : DYYYTaskStateFailed;
      }
      record.progress = success ? 1.0f : record.progress;
      record.finishedAt = [NSDate date];
      if (fileURL) {
          record.fileURL = fileURL.absoluteString;
      }

      [self.historyRecords insertObject:record atIndex:0];
      if (self.historyRecords.count > kDYYYHistoryLimit) {
          [self.historyRecords removeObjectsInRange:NSMakeRange(kDYYYHistoryLimit, self.historyRecords.count - kDYYYHistoryLimit)];
      }
      [self persistHistoryLocked];

      if (record.state == DYYYTaskStateFailed) {
          [DYYYLogger warning:@"TaskCenter" message:[NSString stringWithFormat:@"任务失败 [%@] %@ %@", record.type, record.title, record.detail ?: @""]];
      } else {
          [DYYYLogger debug:@"TaskCenter" message:[NSString stringWithFormat:@"任务结束 [%@] %@", record.type, DYYYTaskStateName(record.state)]];
      }
    });
}

// 调用方需持有 queue 写权限
- (void)persistHistoryLocked {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:self.historyRecords.count];
    for (DYYYTaskRecord *record in self.historyRecords) {
        [array addObject:[record dictionaryRepresentation]];
    }
    [array writeToFile:DYYYHistoryFilePath() atomically:YES];
}

- (NSArray<DYYYTaskRecord *> *)activeTasks {
    [self reloadHistoryIfNeeded];
    __block NSArray<DYYYTaskRecord *> *result;
    dispatch_sync(self.queue, ^{
      result = [[self.activeRecords allValues] copy];
    });
    return [result sortedArrayUsingComparator:^NSComparisonResult(DYYYTaskRecord *a, DYYYTaskRecord *b) {
      return [b.createdAt compare:a.createdAt];
    }] ?: @[];
}

- (NSArray<DYYYTaskRecord *> *)history {
    [self reloadHistoryIfNeeded];
    __block NSArray<DYYYTaskRecord *> *result;
    dispatch_sync(self.queue, ^{
      result = [self.historyRecords copy];
    });
    return result ?: @[];
}

- (NSUInteger)finishedCountToday {
    [self reloadHistoryIfNeeded];
    __block NSUInteger count = 0;
    dispatch_sync(self.queue, ^{
      NSCalendar *calendar = [NSCalendar currentCalendar];
      NSDate *now = [NSDate date];
      for (DYYYTaskRecord *record in self.historyRecords) {
          if (record.finishedAt && [calendar isDate:record.finishedAt inSameDayAsDate:now] && record.state == DYYYTaskStateDone) {
              count++;
          }
      }
    });
    return count;
}

- (void)clearHistory {
    [self reloadHistoryIfNeeded];
    dispatch_barrier_async(self.queue, ^{
      [self.historyRecords removeAllObjects];
      [self persistHistoryLocked];
    });
}

@end
