#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批量抓取 LottieFiles Creator 专业设计文档"""
import re, html, os, urllib.request, time

BASE = "https://docs.lottiefiles.com/en/creator"
OUT = r"C:\Users\XIAO2027\Desktop\客户端\素材\creator-docs"
os.makedirs(OUT, exist_ok=True)

# 核心设计章节（跳过 API 参考）
DOCS = [
    "/01_introduction/overview",
    "/01_introduction/terminology",
    "/02_quickstart/interface",
    "/02_quickstart/canvas",
    "/02_quickstart/first-animation",
    "/03_drawing/shapes",
    "/03_drawing/pen-tool",
    "/03_drawing/path-editing",
    "/04_layers-and-hierarchy/layer-types",
    "/04_layers-and-hierarchy/outliner",
    "/04_layers-and-hierarchy/parenting",
    "/04_layers-and-hierarchy/precompositions",
    "/05_layer-manipulation/anchor-point",
    "/05_layer-manipulation/transform-controls",
    "/06_properties/property-panel-overview",
    "/06_properties/transform-properties",
    "/06_properties/appearance-and-compositing",
    "/07_animation/keyframes",
    "/07_animation/animated-properties",
    "/07_animation/easing",
    "/07_animation/graph-editor",
    "/07_animation/timeline",
    "/07_animation/time-stretch",
    "/07_animation/preview",
    "/07_animation/advanced-duplicator",
    "/08_text/text-property",
    "/09_assets-and-importing/importing",
    "/09_assets-and-importing/asset-manager",
    "/09_assets-and-importing/library",
    "/10_exporting/formats",
    "/10_exporting/how-to-export",
    "/10_exporting/publishing",
    "/11_interactivity-and-state-machines/states",
    "/11_interactivity-and-state-machines/transitions",
    "/11_interactivity-and-state-machines/inputs",
    "/11_interactivity-and-state-machines/interactions",
    "/12_motion-tokens/motion-tokens-in-code",
    "/13_ai-tools/motion-copilot",
    "/13_ai-tools/prompt-to-vector",
    "/13_ai-tools/prompt-to-themes",
    "/13_ai-tools/prompt-to-state-machines",
    "/15_motion-system",
    "/16_reference/glossary",
]

def fetch(path):
    url = BASE + path
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode('utf-8', errors='replace')

def extract(content):
    m = re.search(r'<main[^>]*>(.*?)</main>', content, re.S)
    if not m:
        m = re.search(r'<article[^>]*>(.*?)</article>', content, re.S)
    if not m:
        return None
    text = re.sub(r'<script.*?</script>', '', m.group(1), flags=re.S)
    text = re.sub(r'<style.*?</style>', '', text, flags=re.S)
    text = re.sub(r'<[^>]+>', '\n', text)
    text = html.unescape(text)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n\s*\n+', '\n\n', text)
    return text.strip()

results = {}
for path in DOCS:
    try:
        content = fetch(path)
        text = extract(content)
        if text:
            fname = path.strip('/').replace('/', '_') + '.txt'
            with open(os.path.join(OUT, fname), 'w', encoding='utf-8') as f:
                f.write(text)
            results[path] = len(text)
            print(f"✅ {path} ({len(text)} chars)")
        else:
            print(f"⚠️ {path} 提取失败")
    except Exception as e:
        print(f"❌ {path}: {e}")
    time.sleep(0.3)

print(f"\n共抓取 {len(results)} 篇，保存到 {OUT}")
