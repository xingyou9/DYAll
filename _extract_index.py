import re, io, json, os

os.chdir(os.path.dirname(os.path.abspath(__file__)))
src = io.open('DYYYSettings.xm', encoding='utf-8').read()

cats = [
    (251,  '基本设置'),
    (786,  '界面设置'),
    (967,  '隐藏设置'),
    (1782, '顶栏移除'),
    (1904, '增强设置'),
    (2918, '悬浮按钮'),
]

def cat_for_line(lineno):
    cur = None
    for start, name in cats:
        if lineno >= start:
            cur = name
    return cur

ident_re = re.compile(r'@"identifier"\s*:\s*@"([^"]+)"')
title_re = re.compile(r'@"title"\s*:\s*@"([^"]*)"')
sub_re = re.compile(r'@"subTitle"\s*:\s*@"([^"]*)"')
cell_re = re.compile(r'@"cellType"\s*:\s*@(\d+)')

skip = {'DYYYBasicSettings','DYYYUISettings','DYYYHideSettings','DYYYRemoveSettings','DYYYEnhanceSettings','DYYYFloatButtonSettings','DYYYSpeedSettings','DYYYBackupSettings','DYYYRestoreSettings','DYYYCleanSettings','DYYYCleanCache','DYYYAbout','DYYYSystemSettings','DYYYAutoRestoreSpeed','DYYYSpeedButtonShowX','DYYYEnableFloatClearButtonSize'}

out, seen = [], set()
for im in ident_re.finditer(src):
    start = src.rfind('@{', 0, im.start())
    end = src.find('}', im.start())
    if start < 0 or end < 0:
        continue
    body = src[start:end]
    lineno = src.count('\n', 0, im.start()) + 1
    ident = im.group(1)
    if not ident.startswith('DYYY') or ident in skip:
        continue
    tm = title_re.search(body)
    if not tm:
        continue
    sm = sub_re.search(body)
    cm = cell_re.search(body)
    cat = cat_for_line(lineno)
    if cat is None:
        continue
    if ident in seen:
        continue
    seen.add(ident)
    out.append({'identifier': ident, 'title': tm.group(1), 'subTitle': sm.group(1) if sm else '', 'cellType': int(cm.group(1)) if cm else 0, 'category': cat})

cats_count = {}
for it in out:
    cats_count[it['category']] = cats_count.get(it['category'], 0) + 1
print('extracted:', len(out), cats_count)
json.dump(out, io.open('_search_index.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
