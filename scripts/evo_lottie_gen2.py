#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EVO 素材生成器 v2 — 全部 Lottie 动画 + 静态素材（iOS 优先，无 emoji）"""
import json, os, math

OUT = r"C:\Users\XIAO2027\Desktop\客户端\素材"
os.makedirs(OUT, exist_ok=True)

def shape_layer(ind, name, ty_items, ks, ip=0, op=90, st=0):
    return {"ddd": 0, "ind": ind, "ty": 4, "nm": name, "sr": 1, "ks": ks, "ao": 0,
            "shapes": [{"ty": "gr", "nm": name, "it": ty_items}], "ip": ip, "op": op, "st": st}

def ellipse_item(w, h, name="el"):
    return {"ty": "el", "p": {"a": 0, "k": [0, 0]}, "s": {"a": 0, "k": [w, h]}, "nm": name}

def rect_item(w, h, r=0, name="rc"):
    return {"ty": "rc", "nm": name, "d": 1, "s": {"a": 0, "k": [w, h]},
            "p": {"a": 0, "k": [0, 0]}, "r": {"a": 0, "k": r}}

def fill_item(rgb01, alpha=1.0, name="fill"):
    return {"ty": "fl", "c": {"a": 0, "k": [rgb01[0], rgb01[1], rgb01[2], alpha]},
            "o": {"a": 0, "k": 100}, "nm": name}

def stroke_item(rgb01, width, alpha=1.0, name="stroke"):
    return {"ty": "st", "c": {"a": 0, "k": [rgb01[0], rgb01[1], rgb01[2], alpha]},
            "o": {"a": 0, "k": 100}, "w": {"a": 0, "k": width}, "nm": name}

def tr_item():
    return {"ty": "tr", "p": {"a": 0, "k": [0, 0]}, "a": {"a": 0, "k": [0, 0]},
            "s": {"a": 0, "k": [100, 100]}, "r": {"a": 0, "k": 0}, "o": {"a": 0, "k": 100}}

def kf_rot(frames_deg): return {"a": 1, "k": [{"t": f, "s": [d]} for f, d in frames_deg]}
def kf_pos(frames_xy): return {"a": 1, "k": [{"t": f, "s": [x, y, 0]} for f, (x, y) in frames_xy]}
def kf_scale(frames_xy): return {"a": 1, "k": [{"t": f, "s": [x, y, 100]} for f, (x, y) in frames_xy]}
def kf_opacity(frames_o): return {"a": 1, "k": [{"t": f, "s": [o]} for f, o in frames_o]}
def static(v): return {"a": 0, "k": v}
def base_ks(o=100, r=0, p=(0,0,0), s=(100,100,100)):
    return {"o": static(o), "r": static(r), "p": static(list(p)), "a": static([0,0,0]), "s": static(list(s))}

def save(name, layers, w=256, h=256, fr=30, op=90):
    data = {"v": "5.7.4", "fr": fr, "ip": 0, "op": op, "w": w, "h": h,
            "nm": name, "ddd": 0, "assets": [], "layers": layers}
    path = os.path.join(OUT, name + ".json")
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print(f"✅ {name}.json ({os.path.getsize(path)/1024:.1f}KB)")

# ========== 品牌色 ==========
PURPLE = (0.4627, 0.3412, 1.0)        # #7657FF
PURPLE_DIM = (0.1647, 0.1294, 0.3137) # #2A2150
WHITE_SOFT = (0.9255, 0.9098, 1.0)    # #ECE8FF
TEAL = (0.196, 0.831, 0.514)          # #32D583
GREEN_OK = (0.204, 0.780, 0.349)      # #34C759

# ========== ① AI 助手动态头像（紫底 + 白环旋转 + 光点呼吸） ==========
layers = [
    shape_layer(3, "dot-center", [ellipse_item(24, 24), fill_item(WHITE_SOFT), tr_item()],
        {**base_ks(), "o": kf_opacity([(0,100),(45,30),(90,100)])}),
    shape_layer(2, "ring-white", [ellipse_item(145, 145), stroke_item(WHITE_SOFT, 5), tr_item()],
        {**base_ks(), "r": kf_rot([(0,0),(90,360)])}),
    shape_layer(1, "bg-circle", [ellipse_item(120, 120), fill_item(PURPLE), tr_item()],
        {**base_ks(), "s": kf_scale([(0,(100,100)),(45,(108,108)),(90,(100,100))])}),
]
save("AI助手动态头像", layers)

# ========== ⑥ 通话连接动画（双环脉冲 + 中心圆呼吸） ==========
layers = [
    shape_layer(4, "center-dot", [ellipse_item(36, 36), fill_item(PURPLE), tr_item()],
        {**base_ks(), "s": kf_scale([(0,(100,100)),(45,(120,120)),(90,(100,100))])}),
    shape_layer(3, "ring-pulse-1", [ellipse_item(120, 120), stroke_item(PURPLE, 5), tr_item()],
        {**base_ks(), "o": kf_opacity([(0,80),(90,0)]),
         "s": kf_scale([(0,(100,100)),(90,(160,160))])}),
    shape_layer(2, "ring-pulse-2", [ellipse_item(120, 120), stroke_item(WHITE_SOFT, 4), tr_item()],
        {**base_ks(), "o": kf_opacity([(0,0),(45,60),(90,0)]),
         "s": kf_scale([(0,(100,100)),(90,(150,150))])}),
    shape_layer(1, "bg-circle", [ellipse_item(160, 160), fill_item(PURPLE_DIM), tr_item()],
        base_ks()),
]
save("通话连接动画", layers)

# ========== ⑦ AI 工具加载（三环依次亮起 + 中心脉冲） ==========
layers = []
for i in range(3):
    x = 128 + (i - 1) * 34
    layers.append(shape_layer(6-i, f"dot-{i}", [ellipse_item(20, 20), fill_item(PURPLE), tr_item()],
        {**base_ks(p=(x, 128, 0)),
         "o": kf_opacity([(0,25),(i*10,100),(i*10+15,25),(90,25)]),
         "s": kf_scale([(0,(100,100)),(i*10,(140,140)),(i*10+15,(100,100))])}))
layers.append(shape_layer(1, "ring-tools", [ellipse_item(130, 130), stroke_item(PURPLE, 4), tr_item()],
    {**base_ks(), "r": kf_rot([(0,0),(90,360)])}))
save("AI工具加载", layers)

# ========== ⑧ 发送成功勾选（圆环 + 对勾路径生长） ==========
layers = [
    shape_layer(3, "check", [
        {"ty": "sh", "nm": "check-path", "ind": 0, "ks": {"a": 0, "k": {
            "i": [[0,0],[0,0],[0,0]], "o": [[0,0],[0,0],[0,0]],
            "v": [[-30,-2],[-8,22],[32,-24]], "c": False
        }}},
        stroke_item(GREEN_OK, 10), tr_item()],
        {**base_ks(), "o": kf_opacity([(0,0),(20,0),(40,100),(90,100)]),
         "s": kf_scale([(40,(100,100)),(60,(115,115)),(70,(100,100))])}),
    shape_layer(2, "ring-ok", [ellipse_item(140, 140), stroke_item(GREEN_OK, 6), tr_item()],
        {**base_ks(), "o": kf_opacity([(0,0),(20,0),(40,100),(90,100)]),
         "s": kf_scale([(40,(90,90)),(60,(100,100))])}),
    shape_layer(1, "bg-ok", [ellipse_item(160, 160), fill_item(PURPLE_DIM), tr_item()],
        {**base_ks(), "o": kf_opacity([(0,0),(20,0),(40,100),(90,100)])}),
]
save("发送成功动画", layers)

# ========== ⑨ 连接状态动画（云端 + 信号弧） ==========
layers = [
    shape_layer(3, "cloud", [
        {"ty": "sh", "nm": "cloud-path", "ind": 0, "ks": {"a": 0, "k": {
            "i": [[0,0],[0,-14],[0,0],[0,0],[0,-18],[0,0],[0,0],[14,0],[0,0],[0,0],[0,14],[0,0],[0,0],[-18,0],[0,0]],
            "o": [[0,0],[0,0],[0,14],[0,0],[0,0],[14,0],[0,0],[0,0],[0,-18],[0,0],[0,0],[0,0],[-14,0],[0,0],[0,0]],
            "v": [[-40,12],[-40,-4],[-28,-4],[-28,-18],[2,-18],[2,-34],[28,-34],[52,-34],[52,-18],[64,-18],[64,12],[-40,12],[-40,12],[-40,12],[-40,12]],
            "c": False
        }}},
        fill_item(WHITE_SOFT), tr_item()],
        {**base_ks(), "o": kf_opacity([(0,60),(20,100),(40,60)])}),
    shape_layer(2, "ring-a", [ellipse_item(90, 90), stroke_item(PURPLE, 5), tr_item()],
        {**base_ks(p=(118, 128, 0)), "o": kf_opacity([(0,0),(30,80),(60,0)]),
         "s": kf_scale([(0,(60,60)),(60,(130,130))])}),
    shape_layer(1, "ring-b", [ellipse_item(90, 90), stroke_item(TEAL, 4), tr_item()],
        {**base_ks(p=(118, 128, 0)), "o": kf_opacity([(0,0),(15,70),(45,0)]),
         "s": kf_scale([(0,(60,60)),(45,(120,120))])}),
]
save("连接状态动画", layers, op=60)

print(f"\n✅ 动画全部生成到 {OUT}")
