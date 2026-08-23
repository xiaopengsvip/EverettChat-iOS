import sys

path = sys.argv[1] if len(sys.argv) > 1 else r"D:\EverettChat-iOS\EverettChat\UI\SettingsView.swift"
with open(path, encoding='utf-8') as f:
    src = f.read()

depth = 0
line = 1
in_str = False
i = 0
ok = True
while i < len(src):
    c = src[i]
    if c == '\n':
        line += 1
    if in_str:
        if c == '\\':
            i += 2
            continue
        if c == '"':
            in_str = False
        i += 1
        continue
    if c == '"':
        in_str = True
    elif c == '{':
        depth += 1
    elif c == '}':
        depth -= 1
        if depth < 0:
            print(f"negative depth at line {line}")
            ok = False
            break
    i += 1

print(f"final depth: {depth}  {'OK balanced' if depth == 0 and ok else 'UNBALANCED'}")
