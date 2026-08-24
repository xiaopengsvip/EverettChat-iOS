#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EVO 素材生成器 — 用 Python 生成全部 Lottie JSON 素材（不依赖 Creator 导出）"""
import json, os

OUT = r"C:\Users\XIAO2027\Desktop\客户端\素材"
os.makedirs(OUT, exist_ok=True)

def shape_layer(ind, name, ty_items, ks, ip=0, op=90, st=0):
    return {
        "ddd": 0, "ind": ind, "ty": 4, "nm": name,
        "sr": 1, "ks": ks, "ao": 0,
        "shapes": [{"ty": "gr", "nm": name, "it": ty_items}],
        "ip": ip, "op": op, "st": st
    }

def ellipse_item(w, h, name="el"):
    return {"ty": "el", "p": {"a": 0, "k": [0, 0]}, "s": {"a": 0, "k": [w, h]}, "nm": name}

def fill_item(rgb01, alpha=1.0, name="fill"):
    return {"ty": "fl", "c": {"a": 0, "k": [rgb01[0], rgb01[1], rgb01[2], alpha]}, "o": {"a": 0, "k": 100}, "nm": name}

def stroke_item(rgb01, width, alpha=1.0, name="stroke"):
    return {"ty": "st", "c": {"a": 0, "k": [rgb01[0], rgb01[1], rgb01[2], alpha]},
            "o": {"a": 0, "k": 100}, "w": {"a": 0, "k": width}, "nm": name}

def tr_item():
    return {"ty": "tr", "p": {"a": 0, "k": [0, 0]}, "a": {"a": 0, "k": [0, 0]},
            "s": {"a": 0, "k": [100, 100]}, "r": {"a": 0, "k": 0}, "o": {"a": 0, "k": 100}}

def kf_rot(frames_deg):
    """rotation keyframes: [(frame, deg), ...]"""
    return {"a": 1, "k": [{"t": f, "s": [d]} for f, d in frames_deg]}

def kf_pos(frames_xy):
    return {"a": 1, "k": [{"t": f, "s": [x, y, 0]} for f, (x, y) in frames_xy]}

def kf_scale(frames_xy):
    return {"a": 1, "k": [{"t": f, "s": [x, y, 100]} for f, (x, y) in frames_xy]}

def kf_opacity(frames_o):
    return {"a": 1, "k": [{"t": f, "s": [o]} for f, o in frames_o]}

def static(v):
    return {"a": 0, "k": v}

def base_ks(o=100, r=0, p=(0,0,0), s=(100,100,100)):
    return {"o": static(o), "r": static(r), "p": static(list(p)), "a": static([0,0,0]), "s": static(list(s))}

def save(name, layers, w=256, h=256, fr=30, op=90):
    data = {"v": "5.7.4", "fr": fr, "ip": 0, "op": op, "w": w, "h": h,
            "nm": name, "ddd": 0, "assets": [], "layers": layers}
    path = os.path.join(OUT, name + ".json")
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print(f"✅ {name}.json ({os.path.getsize(path)/1024:.1f}KB)")

# ========== 颜色 ==========
PURPLE = (0.4627, 0.3412, 1.0)     # #7657FF 品牌紫
PURPLE_DIM = (0.1647, 0.1294, 0.3137)  # #2A2150 深紫
WHITE_SOFT = (0.9255, 0.9098, 1.0)  # #ECE8FF 紫调浅色
GRAY_SOFT = (0.898, 0.898, 0.902)   # #E5E5E6 浅灰
GRAY_MID = (0.667, 0.667, 0.671)    # #AAAAAB 中灰
TEAL = (0.196, 0.831, 0.514)        # #32D583 绿

# ========== ① AI 助手动态头像（已有，重新生成统一版） ==========
layers = [
    shape_layer(3, "dot-center", [
        ellipse_item(24, 24), fill_item(WHITE_SOFT), tr_item()],
        {**base_ks(), "o": kf_opacity([(0,100),(45,30),(90,100)])}),
    shape_layer(2, "ring-white", [
        ellipse_item(145, 145), stroke_item(WHITE_SOFT, 5), tr_item()],
        {**base_ks(), "r": kf_rot([(0,0),(90,360)])}),
    shape_layer(1, "bg-circle", [
        ellipse_item(120, 120), fill_item(PURPLE), tr_item()],
        {**base_ks(), "s": kf_scale([(0,(100,100)),(45,(108,108)),(90,(100,100))])}),
]
save("AI助手动态头像", layers)

# ========== ② 默认好友头像（灰色底 + 品牌紫边框 + 人形） ==========
# 灰色圆 + 紫色圆环 + 白色人形（头+肩，简化：用圆+半圆表示）
layers = [
    shape_layer(4, "person-head", [
        ellipse_item(36, 36), fill_item(GRAY_MID), tr_item()],
        {**base_ks(p=(128, 108, 0))}),
    shape_layer(3, "person-body", [
        ellipse_item(70, 44), fill_item(GRAY_MID), tr_item()],
        {**base_ks(p=(128, 168, 0))}),
    shape_layer(2, "ring-brand", [
        ellipse_item(196, 196), stroke_item(PURPLE, 6), tr_item()],
        {**base_ks(), "r": kf_rot([(0,0),(150,360)])}),
    shape_layer(1, "bg-gray", [
        ellipse_item(180, 180), fill_item(GRAY_SOFT), tr_item()],
        base_ks()),
]
save("默认好友头像", layers, op=150)

# ========== ③ AI 思考加载动画（紫色圆环旋转 + 3 光点环绕） ==========
layers = []
# 3 个光点环绕（位置动画）
for i, (color, phase) in enumerate([(PURPLE, 0), (WHITE_SOFT, 30), (TEAL, 60)]):
    frames = []
    for f in range(0, 91, 15):
        ang = (f + phase) * 4  # 360/90帧
        import math
        rad = math.radians(ang)
        x = 128 + 60 * math.cos(rad)
        y = 128 + 60 * math.sin(rad)
        frames.append((f, (round(x), round(y))))
    layers.append(shape_layer(5-i, f"dot-{i}", [
        ellipse_item(22, 22), fill_item(color), tr_item()],
        {**base_ks(), "p": kf_pos(frames)}))
# 外层圆环旋转
layers.append(shape_layer(1, "ring-load", [
    ellipse_item(140, 140), stroke_item(PURPLE, 6), tr_item()],
    {**base_ks(), "r": kf_rot([(0,0),(90,360)])}))
save("AI思考加载", layers)

# ========== ④ 消息发送动画（纸飞机简化：箭头飞出） ==========
# 圆圈 + 箭头（三角形用 polygon）
layers = [
    shape_layer(3, "arrow", [
        {"ty": "sh", "nm": "arrow-path", "ks": {"a": 0, "k": {
            "i": [[0,0],[0,0],[0,0]], "o": [[0,0],[0,0],[0,0]],
            "v": [[-18,-12],[18,0],[-18,12]], "c": True
        }}, "ind": 0},
        fill_item(PURPLE), tr_item()],
        {**base_ks(p=(100, 128, 0)), "p": kf_pos([(0,(100,128)),(20,(156,128))]),
         "o": kf_opacity([(0,100),(20,0)])}),
    shape_layer(2, "ring-send", [
        ellipse_item(120, 120), stroke_item(PURPLE, 5), tr_item()],
        base_ks()),
    shape_layer(1, "bg-send", [
        ellipse_item(160, 160), fill_item(PURPLE_DIM), tr_item()],
        base_ks()),
]
save("消息发送动画", layers, op=20)

# ========== ⑤ 录音波形动画（5 根竖条波动） ==========
layers = []
for i in range(5):
    x = 96 + i * 16
    frames = []
    for f in range(0, 61, 15):
        import math
        hgt = 18 + 16 * abs(math.sin((f + i*10) / 60 * 3.14159 * 2))
        frames.append((f, (100, round(hgt))))
    layers.append(shape_layer(5-i, f"bar-{i}", [
        {"ty": "rc", "nm": "rect", "d": 1,
         "s": {"a": 0, "k": [8, 20]}, "p": {"a": 0, "k": [0, 0]}, "r": {"a": 0, "k": 2}},
        fill_item(PURPLE if i != 2 else TEAL), tr_item()],
        {**base_ks(p=(x, 128, 0)), "s": kf_scale([(f, (100, h)) for f, (_, h) in frames])}))
save("录音波形", layers, op=60)

print(f"\n全部素材已生成到: {OUT}")
for f in sorted(os.listdir(OUT)):
    print(f"  {f}")
