path = r"D:\EverettChat-iOS\EverettChat\UI\ChatView.swift"
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

# 定位 body 内的逻辑链：.onAppear 到 .onDisappear
    onappear_idx = None
    last_onchange_idx = None
    for i, l in enumerate(lines):
        if l.strip().startswith('.onAppear'):
            if onappear_idx is None:
                onappear_idx = i
        if l.strip().startswith('.onDisappear'):
            last_onchange_idx = i
    assert onappear_idx is not None and last_onchange_idx is not None, f"{onappear_idx} {last_onchange_idx}"

logic_chain = lines[onappear_idx:last_onchange_idx + 1]
print(f"逻辑链: {onappear_idx}..{last_onchange_idx} ({len(logic_chain)} 行)")

# 从 body 中删除逻辑链（保留前后）
# body 结构：mainBody + sheet链 + 逻辑链 + }
# 删除后：mainBody + sheet链 + }
del lines[onappear_idx:last_onchange_idx + 1]

# 找 mainBody 的 .animation(showVoiceHint)（mainBody modifier 链末尾）
anim_idx = None
for i, l in enumerate(lines):
    if '.animation(.easeInOut(duration: 0.2), value: showVoiceHint)' in l:
        anim_idx = i
        break
assert anim_idx is not None

# 在 .animation 后插入逻辑链（挂在 mainBody 的 VStack 上）
insert_at = anim_idx + 1
logic_indented = [l if l.strip().startswith('.') else l for l in logic_chain]
lines[insert_at:insert_at] = logic_chain

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print(f"✅ 逻辑链已移动到 mainBody (插入到行 {insert_at})")
