"""DAILYREPORT양식.htm (Word HTML, UTF-16) → 일일 보고서 .doc 템플릿.
서식·표 크기는 그대로 두고, 데이터 값만 {{KEY}} 자리표시로 바꾼다.
반복 행은 첫 행을 원형으로 남겨 {{#NAME}}...{{/NAME}} 으로 감싸고 나머지 예시 행은 지운다."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dr_tables import tables, plain

src, dst, report = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src, 'rb').read().decode('utf-16')

def rows(tbl):
    return [m for m in re.finditer(r'<tr\b.*?</tr>', tbl, flags=re.S)]

def cells(row):
    return [m for m in re.finditer(r'<td\b.*?</td>', row, flags=re.S)]

def set_para(cell, key):
    m = re.search(r'(<p\b[^>]*>)(.*?)(</p>)', cell, flags=re.S)
    assert m, cell[:200]
    inner = '<b>{{%s}}</b>' % key if '<b>' in m.group(2) else '{{%s}}' % key
    return cell[:m.start()] + m.group(1) + inner + m.group(3) + cell[m.end():]

def edit_cells(row, keys):
    cs = cells(row)
    assert len(cs) >= len(keys), (len(cs), keys)
    out, pos = '', 0
    for c, k in zip(cs, keys):
        out += row[pos:c.start()] + (set_para(c.group(), k) if k else c.group())
        pos = c.end()
    return out + row[pos:]

def edit_table(idx, fn):
    global t
    s, e, _ = tables(t)[idx]
    t = t[:s] + fn(t[s:e]) + t[e:]

def repeat_rows(name, ncols, keep_last=None):
    """header=row0, prototype=row1; 나머지 데이터 행 삭제. keep_last 키가 있으면 마지막 행(합계)은 남겨 값만 치환."""
    def fn(tbl):
        rs = rows(tbl)
        proto = edit_cells(rs[1].group(), ['C%d' % i for i in range(ncols)])
        last = rs[-1]
        end_cut = last.start() if keep_last else last.end()
        tail = edit_cells(last.group(), keep_last) if keep_last else ''
        return tbl[:rs[1].start()] + '{{#%s}}' % name + proto + '{{/%s}}' % name + tail + tbl[last.end():] if keep_last \
            else tbl[:rs[1].start()] + '{{#%s}}' % name + proto + '{{/%s}}' % name + tbl[end_cut:]
    return fn

# 0. 문서 정보
edit_table(0, lambda tb: (lambda rs: tb[:rs[0].start()]
    + edit_cells(rs[0].group(), [None, 'DOC_NO', None, 'DOC_AT']) + tb[rs[0].end():rs[1].start()]
    + edit_cells(rs[1].group(), [None, 'PROD_DATE', None, 'SHIFT']) + tb[rs[1].end():rs[2].start()]
    + edit_cells(rs[2].group(), [None, None, None, 'STATUS']) + tb[rs[2].end():])(rows(tb)))
# 1. 요약 카드
edit_table(1, lambda tb: (lambda rs: tb[:rs[1].start()]
    + edit_cells(rs[1].group(), ['SUM_PLAN', 'SUM_ACTUAL', 'SUM_RATE', 'SUM_DEFECT']) + tb[rs[1].end():])(rows(tb)))
# 2. 생산 종합 현황 문장
edit_table(2, lambda tb: (lambda rs: tb[:rs[0].start()] + edit_cells(rs[0].group(), ['SUMMARY_TEXT']) + tb[rs[0].end():])(rows(tb)))
# 3. 라인별 실적 (반복 행 + 합계 행)
edit_table(3, repeat_rows('LINES', 6, keep_last=['TOTAL_0', 'TOTAL_1', 'TOTAL_2', 'TOTAL_3', None, 'TOTAL_5']))
# 5. 설비 종합 지표 (굵은 값만)
def metrics(tb):
    n = 0
    def rep(m):
        nonlocal n
        cell = m.group()
        bs = list(re.finditer(r'<b>(?:(?!</b>).)*</b>', cell, flags=re.S))
        assert bs, cell[:200]
        b = bs[-1]
        out = cell[:b.start()] + '<b>{{M%d}}</b>' % n + cell[b.end():]
        n += 1
        return out
    out = re.sub(r'<td\b.*?</td>', rep, tb, flags=re.S)
    assert n == 4, n
    return out
edit_table(5, metrics)
# 6. 공정별 생산·불량
edit_table(6, repeat_rows('PROC', 4))
# 7. 설비 비가동 (데이터 1행 = 원형)
edit_table(7, lambda tb: (lambda rs: tb[:rs[1].start()] + '{{#DOWN}}' + edit_cells(rs[1].group(), ['C0', 'C1', 'C2', 'C3']) + '{{/DOWN}}' + tb[rs[-1].end():])(rows(tb)))
# 9. 재공품
edit_table(9, repeat_rows('WIP', 3))
# 8. AI 마감 검토 / 품질 요약 문단
for key, needle in [('AI_REVIEW', '비가동으로'), ('QUALITY', '총 불량은')]:
    pat = r'(<p\b[^>]*>)(?:(?!<p\b|</p>).)*%s(?:(?!</p>).)*(</p>)' % needle
    t, n = re.subn(pat, lambda m: m.group(1) + '{{%s}}' % key + m.group(2), t, count=1, flags=re.S)
    assert n == 1, key
# 10. 인계사항 (첫 문단 = 원형)
def handover(tb):
    ps = list(re.finditer(r'(<p\b[^>]*>)(.*?)(</p>)', tb, flags=re.S))
    assert len(ps) == 3, len(ps)
    proto = ps[0].group(1) + '{{C0}}' + ps[0].group(3)
    return tb[:ps[0].start()] + '{{#HANDOVER}}' + proto + '{{/HANDOVER}}' + tb[ps[-1].end():]
edit_table(10, handover)

# 문서 제목, 외부 .files 링크 제거
t, n = re.subn(r'<title>.*?</title>', '<title>{{DOC_NO}}</title>', t, count=1, flags=re.S); assert n == 1
t = re.sub(r'<link rel=(?:File-List|themeData|colorSchemeMapping)[^>]*>\s*', '', t)

open(dst, 'wb').write(b'\xff\xfe' + t.encode('utf-16-le'))

body = plain(t[t.index('<body'):])
leftovers = [v for v in ['DAILY-2026', '18:03:22', '1,164', '78.4', '86.1', '1212', '3:39:48', '31롤', '31 롤', 'L2 비가동', '총 불량은', '야간조에 인계', '검토 대기'] if v in body]
with open(report, 'w', encoding='utf-8') as f:
    f.write('placeholders: %s\n' % sorted(set(re.findall(r'\{\{[#/]?\w+\}\}', t))))
    f.write('sample values left: %s\n' % leftovers)
    f.write('tables: %d\n' % len(tables(t)))
