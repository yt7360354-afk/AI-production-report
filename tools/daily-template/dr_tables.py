import re, sys

def tables(t):
    """Return (start, end, depth) spans for every <table>, handling nesting."""
    out, stack = [], []
    for m in re.finditer(r'<table\b|</table>', t):
        if m.group().startswith('<table'):
            stack.append(m.start())
        else:
            s = stack.pop()
            out.append((s, m.end(), len(stack)))
    return sorted(out)

def plain(s):
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', s)).replace('&nbsp;', '').strip()

if __name__ == '__main__':
    t = open(sys.argv[1], 'rb').read().decode('utf-16')
    with open(sys.argv[2], 'w', encoding='utf-8') as f:
        for i, (s, e, d) in enumerate(tables(t)):
            f.write(f'{i}: depth={d} rows={t[s:e].count("<tr")} :: {plain(t[s:e])[:70]}\n')
