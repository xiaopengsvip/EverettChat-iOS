#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
EVO APK 推送更新服务（Hermes → 所有在线安卓设备）
用法:
  python evo_push_apk.py <apk路径> [--target 设备ID]

流程:
  1. 读 APK → base64
  2. 计算房间密钥 (PBKDF2-HMAC-SHA256, 与设备端 v1 协议一致)
  3. 加密 FileMeta JSON (AES-256-GCM, nonce 12B)
  4. POST /apk/broadcast → relay 存文件 + 广播给所有设备
  5. 设备收到 file 消息 → 下载 → 弹"安装更新"框
"""
import base64
import hashlib
import json
import os
import sys
import urllib.request

# 绕过系统代理
for k in ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy']:
    os.environ.pop(k, None)

RELAY = 'https://relay.vios.top'
ROOM = 'everett-public'
PASSPHRASE = 'everett-public'
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'


def room_salt(room_id):
    """与设备端一致: salt = SHA256('everett-e2e-v1|' + roomId)[0..16]"""
    return hashlib.sha256(f'everett-e2e-v1|{room_id}'.encode()).digest()[:16]


def derive_key(passphrase, salt, iterations=100000):
    return hashlib.pbkdf2_hmac('sha256', passphrase.encode(), salt, iterations, 32)


def aes_gcm_encrypt(key, plaintext):
    """AES-256-GCM: nonce 12B 随机, 返回 (nonce_b64, ct_with_tag_b64)"""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, plaintext, None)
    return base64.b64encode(nonce).decode(), base64.b64encode(ct).decode()


def http_post(path, data, raw=False):
    if raw:
        req = urllib.request.Request(RELAY + path, data=data,
            headers={'User-Agent': UA, 'Content-Type': 'application/octet-stream'})
    else:
        body = json.dumps(data).encode()
        req = urllib.request.Request(RELAY + path, data=body,
            headers={'User-Agent': UA, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def main():
    if len(sys.argv) < 2:
        print("用法: python evo_push_apk.py <apk路径> [--target 设备ID]")
        return
    apk_path = sys.argv[1]
    target = None
    if '--target' in sys.argv:
        target = sys.argv[sys.argv.index('--target') + 1]

    if not os.path.exists(apk_path):
        print(f"❌ APK 不存在: {apk_path}")
        return

    # 1. 读 APK
    with open(apk_path, 'rb') as f:
        apk_data = f.read()
    size = len(apk_data)
    file_id = f'apk-{int(__import__("time").time())}'
    name = os.path.basename(apk_path)
    print(f"📦 APK: {name} ({size/1024/1024:.1f} MB)")

    # 2. 计算密钥
    salt = room_salt(ROOM)
    key = derive_key(PASSPHRASE, salt)
    print(f"🔑 房间密钥: {base64.b64encode(key).decode()[:24]}... (PBKDF2-100k, E2Ev1)")

    # 3. 加密 FileMeta（与设备端 v1 协议一致）
    meta = {"fileId": file_id, "name": name, "size": size,
            "mime": "application/vnd.android.package-archive"}
    nonce_b64, ct_b64 = aes_gcm_encrypt(key, json.dumps(meta).encode())
    print(f"🔒 已加密 FileMeta (nonce={nonce_b64[:12]}...)")

    # 4. 上传 APK 本体（/upload 二进制）+ 广播 meta
    print("📤 上传 APK 到 relay...")
    upload_url = f"{RELAY}/upload?room={ROOM}&fileId={file_id}"
    req = urllib.request.Request(upload_url, data=apk_data,
        headers={'User-Agent': UA, 'Content-Type': 'application/octet-stream'})
    with urllib.request.urlopen(req, timeout=300) as r:
        up = json.loads(r.read())
    if not up.get('ok'):
        print(f"❌ 上传失败: {up}")
        return
    print(f"✅ 上传完成 ({size/1024/1024:.1f} MB)")

    # 5. 广播 file 消息（只带加密 meta）
    payload = {
        "fileId": file_id, "name": name, "size": size,
        "mime": "application/vnd.android.package-archive",
        "encMeta": ct_b64, "nonce": nonce_b64, "salt": base64.b64encode(salt).decode()
    }
    print("📡 广播到在线设备...")
    r = http_post('/apk/broadcast', payload)
    if r.get('ok'):
        print(f"✅ 已广播给 {r.get('sent', 0)} 台在线设备")
        print(f"   fileId: {file_id}")
        print(f"   设备收到后会自动弹「安装更新」")
        if target:
            print(f"   (定向: {target[:8]})")
    else:
        print(f"❌ 广播失败: {r}")


if __name__ == '__main__':
    main()
