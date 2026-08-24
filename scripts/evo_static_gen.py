#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EVO 静态素材生成器 — 品牌 Logo + 空状态插画（PNG，透明背景，无 emoji）"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = r"C:\Users\XIAO2027\Desktop\客户端\素材"
os.makedirs(OUT, exist_ok=True)

PURPLE = (118, 87, 255)       # #7657FF
PURPLE_DIM = (42, 33, 80)     # #2A2150
PURPLE_LIGHT = (233, 228, 255) # #E9E4FF
WHITE = (255, 255, 255)
GRAY = (170, 170, 171)
GRAY_LIGHT = (229, 229, 230)

# 找中文字体（Windows）
FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyhbd.ttc",   # 微软雅黑 Bold
    r"C:\Windows\Fonts\msyh.ttc",     # 微软雅黑
    r"C:\Windows\Fonts\simhei.ttf",   # 黑体
    r"C:\Windows\Fonts\arialbd.ttf",  # Arial Bold
]
def find_font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except: pass
    return ImageFont.load_default()

# ========== ① 品牌 Logo（透明 PNG：紫色圆 + EVO 字） ==========
def make_logo(size=512):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 紫色渐变圆（两层叠加模拟渐变）
    r = size * 0.42
    cx = cy = size // 2
    # 外圈深紫
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=PURPLE)
    # 高光（上半偏亮）
    hr = r * 0.85
    d.ellipse([cx-hr, cy-hr*0.85, cx+hr, cy+hr*0.2], fill=(140, 118, 255, 120))
    # EVO 文字
    font = find_font(int(size * 0.24))
    text = "EVO"
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    d.text((cx - tw/2 - bbox[0], cy - th/2 - bbox[1]), text, fill=WHITE, font=font)
    img.save(os.path.join(OUT, "品牌Logo.png"))
    print(f"✅ 品牌Logo.png ({size}x{size})")

# ========== ② 空状态插画（消息空：气泡 + 聊天气泡轮廓） ==========
def make_empty_message(size=512):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = size//2, size//2
    # 大聊天气泡（浅紫圆角矩形 + 三角尾巴）
    bw, bh = size*0.62, size*0.42
    bx0, by0 = cx-bw/2, cy-bh/2 - size*0.06
    bx1, by1 = cx+bw/2, cy+bh/2 - size*0.06
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=int(size*0.1), fill=PURPLE_LIGHT)
    # 气泡尾巴（三角）
    tail = [(bx0 + size*0.12, by1), (bx0 + size*0.12 + size*0.09, by1 + size*0.09), (bx0 + size*0.12 + size*0.18, by1)]
    d.polygon(tail, fill=PURPLE_LIGHT)
    # 三条"消息"线条（灰）
    line_color = (200, 195, 220)
    for i, lw in enumerate([0.5, 0.36, 0.24]):
        lw_px = bw * lw
        ly = by0 + size*0.12 + i * size*0.12
        d.rounded_rectangle([cx-lw_px/2, ly, cx+lw_px/2, ly + size*0.045],
                            radius=int(size*0.02), fill=line_color)
    # 小气泡（右上，淡紫）
    sw = size*0.28
    sx0, sy0 = cx + bw*0.35, by0 - size*0.12
    sx1, sy1 = sx0 + sw, sy0 + sw*0.5
    d.rounded_rectangle([sx0, sy0, sx1, sy1], radius=int(size*0.05), fill=(216, 208, 250, 200))
    img.save(os.path.join(OUT, "空状态消息.png"))
    print(f"✅ 空状态消息.png ({size}x{size})")

# ========== ③ 空状态通讯录（人形轮廓 + 加号） ==========
def make_empty_contacts(size=512):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = size//2, size//2
    # 人形（头 + 肩，浅灰）
    head_r = size*0.13
    d.ellipse([cx-head_r, cy-size*0.18-head_r, cx+head_r, cy-size*0.18+head_r], fill=GRAY_LIGHT)
    # 肩（半圆）
    shoulder_w = size*0.36
    d.pieslice([cx-shoulder_w, cy-size*0.05, cx+shoulder_w, cy+size*0.35],
               180, 360, fill=GRAY_LIGHT)
    # 紫色圆环（品牌色）
    ring_r = size*0.38
    d.ellipse([cx-ring_r, cy-ring_r, cx+ring_r, cy+ring_r],
              outline=PURPLE, width=int(size*0.02))
    # 右上角加号（紫色）
    plus_size = size*0.11
    px, py = cx + ring_r*0.75, cy - ring_r*0.75
    d.rounded_rectangle([px-plus_size/2, py-size*0.015, px+plus_size/2, py+size*0.015],
                        radius=3, fill=PURPLE)
    d.rounded_rectangle([px-size*0.015, py-plus_size/2, px+size*0.015, py+plus_size/2],
                        radius=3, fill=PURPLE)
    img.save(os.path.join(OUT, "空状态通讯录.png"))
    print(f"✅ 空状态通讯录.png ({size}x{size})")

# ========== ④ 空状态发现（网格卡片 + 探索图标） ==========
def make_empty_discover(size=512):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = size//2, size//2
    # 2x2 网格卡片（浅紫圆角矩形）
    card_w = size*0.3
    gap = size*0.06
    card_r = int(size*0.06)
    for row in range(2):
        for col in range(2):
            x0 = cx - card_w - gap/2 + col*(card_w+gap)
            y0 = cy - card_w - gap/2 + row*(card_w+gap)
            alpha = 255 - (row+col)*40
            d.rounded_rectangle([x0, y0, x0+card_w, y0+card_w], radius=card_r,
                                fill=(233, 228, 255, alpha))
    # 中心放大镜（品牌紫）
    ring_r = size*0.1
    lx, ly = cx - size*0.02, cy - size*0.04
    d.ellipse([lx-ring_r, ly-ring_r, lx+ring_r, ly+ring_r],
              outline=PURPLE, width=int(size*0.022))
    # 放大镜柄
    hx1, hy1 = lx + ring_r*0.7, ly + ring_r*0.7
    hx2, hy2 = lx + ring_r*1.35, ly + ring_r*1.35
    d.line([hx1, hy1, hx2, hy2], fill=PURPLE, width=int(size*0.022))
    img.save(os.path.join(OUT, "空状态发现.png"))
    print(f"✅ 空状态发现.png ({size}x{size})")

make_logo(512)
make_empty_message(512)
make_empty_contacts(512)
make_empty_discover(512)
print(f"\n✅ 静态素材全部生成到 {OUT}")
