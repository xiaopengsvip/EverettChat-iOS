import sys

path = r"D:\EverettChat-iOS\EverettChat\UI\ChatView.swift"
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

# 找 ChatView 的 body（第 65 行附近，前面是 @State prevConnected）
body_start = None
for i, l in enumerate(lines):
    if 'var body: some View {' in l and i < 200:
        # 确认前面有 showConnBanner
        if any('showConnBanner' in lines[j] for j in range(max(0, i-8), i)):
            body_start = i
            break
assert body_start is not None, "ChatView body 未找到"

vstack_start = body_start + 1
assert 'VStack(spacing: 0)' in lines[vstack_start], f"VStack 未找到: {lines[vstack_start]}"

# 括号匹配找 VStack 闭合
depth = 0
vstack_end = None
for i in range(vstack_start, len(lines)):
    depth += lines[i].count('{') - lines[i].count('}')
    if depth == 0:
        vstack_end = i
        break
assert vstack_end is not None

# modifier 链结束（第一个 .sheet 前）
modifier_end = vstack_end
for i in range(vstack_end + 1, len(lines)):
    stripped = lines[i].strip()
    if stripped.startswith('.sheet(') or stripped.startswith('.fullScreenCover(') or stripped.startswith('.confirmationDialog(') or stripped.startswith('.photosPicker('):
        modifier_end = i - 1
        break
    if stripped.startswith('private var') or stripped.startswith('struct ') or stripped.startswith('func '):
        modifier_end = i - 1
        break

# body 的弹层链：modifier_end+1 到 struct 结束前的 body } 
# 找 struct ChatView 的闭合：文件里 body 内容结束后的第一个顶层 } 
# 简化：弹层链直到下一个顶层 "struct " 定义前的 }
# 从 modifier_end+1 开始收集，直到遇到缩进为 0 的 }（body 闭合）或下一个 struct/func
sheet_chain = []
i = modifier_end + 1
while i < len(lines):
    stripped = lines[i].strip()
    if stripped == '}' and not lines[i].startswith(' '):
        # body 的闭合 }
        i += 1
        break
    sheet_chain.append(lines[i])
    i += 1

# 弹层链的最后可能包含 struct 的其他成员？不会，body 的 } 就是 body 结束
# 但 sheet_chain 可能包含了 body 闭合 } 之后的空行/注释，截断

vstack_inner = lines[vstack_start + 1:vstack_end]
modifier_chain = lines[vstack_end + 1:modifier_end + 1]

new_code = [
    '    var body: some View {\n',
    '        mainBody\n',
]
new_code.extend(sheet_chain)
new_code.append('    }\n')
new_code.append('\n')
new_code.append('    /// 主内容（VStack：连接状态条 + 顶栏 + 消息列表 + 输入栏）\n')
new_code.append('    private var mainBody: some View {\n')
new_code.append('        VStack(spacing: 0) {\n')
new_code.extend(vstack_inner)
new_code.append('        }\n')
new_code.extend(modifier_chain)
new_code.append('    }\n')

# 替换 [body_start, i) 为 new_code（i 是 body } 之后的下一行）
result = lines[:body_start] + new_code + lines[i:]

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(result)

print(f"✅ 重写完成 body_start={body_start} vstack_end={vstack_end} modifier_end={modifier_end} sheet_chain={len(sheet_chain)} 行")
