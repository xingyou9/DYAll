import io, json, os

os.chdir(os.path.dirname(os.path.abspath(__file__)))
items = json.load(io.open('_search_index.json', encoding='utf-8'))

def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

header = '''#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 全局设置搜索索引（自动生成，勿手改）
 *
 * 数据来自 DYYYSettings.xm 中的设置项字典，共 %d 项。
 * 重新生成：修改设置页后运行提取脚本即可。
 */
NSArray<NSDictionary<NSString *, id> *> *DYYYSettingsSearchIndex(void);

NS_ASSUME_NONNULL_END
''' % len(items)

lines = []
lines.append('#import "DYYYSettingsIndex.h"\n')
lines.append('NSArray<NSDictionary<NSString *, id> *> *DYYYSettingsSearchIndex(void) {')
lines.append('    static NSArray *index = nil;')
lines.append('    static dispatch_once_t onceToken;')
lines.append('    dispatch_once(&onceToken, ^{')
lines.append('        index = @[')
for it in items:
    lines.append('            @{ @"id" : @"%s", @"title" : @"%s", @"sub" : @"%s", @"cell" : @%d, @"cat" : @"%s" },' % (
        esc(it['identifier']), esc(it['title']), esc(it['subTitle']), it['cellType'], esc(it['category'])))
lines.append('        ];')
lines.append('    });')
lines.append('    return index;')
lines.append('}')
io.open('DYYYSettingsIndex.h', 'w', encoding='utf-8').write(header)
io.open('DYYYSettingsIndex.m', 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print('written DYYYSettingsIndex.h/.m with', len(items), 'entries')
