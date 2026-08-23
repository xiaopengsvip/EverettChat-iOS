#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
EVO 更新推送工具（通用版）—— 按平台分发 APK / IPA

用法:
  # 查在线设备（含平台信息）
  python evo_push_update.py --list

  # 推 APK 给所有安卓设备
  python evo_push_update.py <apk路径> --platform android

  # 推 IPA 给所有 iOS 设备
  python evo_push_update.py <ipa路径> --platform ios

  # 推给指定设备
  python evo_push_update.py <包路径> --target 设备ID

  # 推给所有设备（不区分平台）
  python evo_push_update.py <包路径> --all
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

import urllib.request as _ur
# Windows 注册表代理也禁用（urllib 默认会读注册表）
_proxy_handler = _ur.ProxyHandler({})
_opener = _ur.build_opener(_proxy_handler)
_ur.install_opener(_opener)

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
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read())


def http_get(path):
    req = urllib.request.Request(RELAY + path, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def android_name(sdk):
    """SDK → Android 版本名"""
    if not sdk: return '?'
    return {33:'13', 34:'14', 35:'15', 36:'16', 37:'17'}.get(sdk, str(sdk))


def list_devices():
    """查询在线设备, 显示平台/版本"""
    d = http_get('/users')
    print(f"🌐 在线设备 ({len(d['users'])} 台, 中继: {d.get('nodeName','?')})")
    print(f"{'设备名':<12} {'平台':<8} {'版本':<16} 设备ID")
    print("-" * 60)
    android = ios = unknown = 0
    for u in d['users']:
        plat = u.get('platform', '?')
        ver = u.get('version', '?')
        if plat == 'android': android += 1
        elif plat == 'ios': ios += 1
        else: unknown += 1
        print(f"  {u['name']:<10} {plat:<8} {ver:<16} {u['deviceId'][:12]}")
    print(f"\n📊 汇总: 📱 安卓 {android}  | 🍎 iOS {ios}  | ❓ 未知 {unknown}")
    return d['users']


def query_versions(users):
    """向每台在线设备发 version 命令, 显示含 Android 系统版本"""
    import time
    print("\n🔍 查询设备详情...")
    for u in users:
        did = u['deviceId']
        try:
            req = urllib.request.Request(RELAY + '/cmd',
                data=json.dumps({'target': did, 'cmd': 'version'}).encode(),
                headers={'User-Agent': UA, 'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=10) as r:
                rid = json.loads(r.read()).get('requestId', '')
        except Exception as e:
            print(f"  {u['name']}: 命令发送失败 ({e})")
            continue
        got = None
        for _ in range(6):
            time.sleep(1.2)
            try:
                req2 = urllib.request.Request(RELAY + f'/cmd/result?requestId={rid}',
                    headers={'User-Agent': UA})
                with urllib.request.urlopen(req2, timeout=8) as r:
                    res = json.loads(r.read())
                if res.get('status') == 'done':
                    got = res.get('result', {})
                    break
            except Exception:
                pass
        if got:
            model = got.get('model', '?')
            sdk = got.get('sdk', 0)
            print(f"  ✅ {got.get('deviceName', u['name'])}: "
                  f"系统: Android {android_name(sdk)} (SDK {sdk}) · {model} | "
                  f"应用: EVO {got.get('version', '?')} · E2E{got.get('e2e', '?')}")
        else:
            print(f"  ⚠️ {u['name']}: 离线或无回复")


def push_update(apk_path, platform=None, target=None, all_devices=False):
    if not os.path.exists(apk_path):
        print(f"❌ 文件不存在: {apk_path}")
        return

    # 查在线设备
    users = list_devices()
    if not users:
        print("⚠️ 没有在线设备，无法推送")
        return

    # 确定目标平台
    name = os.path.basename(apk_path)
    ext = os.path.splitext(name)[1].lower()
    auto_platform = 'android' if ext == '.apk' else ('ios' if ext == '.ipa' else None)

    # 过滤
    target_ids = []
    matched = []
    if target:
        target_ids = [target]
        matched = [u for u in users if u['deviceId'].startswith(target) or u['deviceId'] == target]
        print(f"🎯 定向推送: {target[:16]}")
    elif all_devices:
        platform = None
        matched = users
        print(f"📡 推送至所有设备（不区分平台）")
    elif platform:
        matched = [u for u in users if u.get('platform') == platform]
        if not matched:
            # 未知平台的设备也包含（兼容旧版设备）
            matched = [u for u in users if u.get('platform') in (platform, 'unknown', '?')]
            if matched:
                print(f"⚠️ 没有明确标记为 {platform} 的设备，将推送给 {len(matched)} 台未知平台设备")
        print(f"📡 推送至平台: {platform}")
    else:
        # 自动推断：从文件扩展名
        platform = auto_platform
        if platform:
            matched = [u for u in users if u.get('platform') in (platform, 'unknown', '?')]
            print(f"📡 自动推断平台: {platform}")
        else:
            matched = users
            print(f"📡 推送至所有设备（无法推断平台）")

    if not matched:
        print(f"❌ 没有匹配的设备")
        return

    print(f"  匹配设备: {len(matched)} 台")
    for u in matched:
        print(f"    → {u['name']:<10} ({u.get('platform','?'):<8}) {u['deviceId'][:12]}")

    # 读文件
    with open(apk_path, 'rb') as f:
        file_data = f.read()
    size = len(file_data)
    file_id = f'update-{int(__import__("time").time())}'
    version_str = ''

    # 尝试从 APK 读取 versionName（用 aapt2，Windows 下用盘符路径避免 MSYS 转换问题）
    if ext == '.apk':
        try:
            import subprocess, glob
            sdk_root = os.environ.get('ANDROID_HOME') or os.path.expanduser(r'~\AppData\Local\Android\Sdk')
            aapt2s = glob.glob(os.path.join(sdk_root, 'build-tools', '*', 'aapt2.exe'))
            if aapt2s:
                aapt2 = sorted(aapt2s)[-1]
                win_path = apk_path.replace('/', '\\')
                out = subprocess.run([aapt2, 'dump', 'badging', win_path],
                    capture_output=True, text=True, timeout=60).stdout
                for line in out.splitlines():
                    if line.startswith("package:"):
                        m = __import__('re').search(r"versionName='([^']+)'", line)
                        if m:
                            version_str = m.group(1)
                        break
                if version_str:
                    print(f"  📋 应用版本: {version_str}")
        except Exception as e:
            print(f"  (读取版本失败: {e})")

    print(f"\n📦 {name} ({size/1024/1024:.1f} MB)" + (f" · v{version_str}" if version_str else ""))

    # 计算密钥 + 加密 meta
    salt = room_salt(ROOM)
    key = derive_key(PASSPHRASE, salt)
    meta = {"fileId": file_id, "name": name, "size": size,
            "mime": "application/vnd.android.package-archive" if ext == '.apk'
                    else "application/octet-stream"}
    nonce_b64, ct_b64 = aes_gcm_encrypt(key, json.dumps(meta).encode())
    print(f"🔒 已加密 FileMeta (E2Ev1, PBKDF2-100k)")

    # 上传
    print(f"📤 上传文件到 relay...")
    upload_url = f"{RELAY}/upload?room={ROOM}&fileId={file_id}"
    req = urllib.request.Request(upload_url, data=file_data,
        headers={'User-Agent': UA, 'Content-Type': 'application/octet-stream'})
    with urllib.request.urlopen(req, timeout=300) as r:
        up = json.loads(r.read())
    if not up.get('ok'):
        print(f"❌ 上传失败: {up}")
        return
    print(f"✅ 上传完成 ({size/1024/1024:.1f} MB)")

    # 广播
    payload = {
        "fileId": file_id, "name": name, "size": size,
        "mime": meta["mime"],
        "encMeta": ct_b64, "nonce": nonce_b64, "salt": base64.b64encode(salt).decode(),
        "platform": platform or '',
        "version": version_str or '',
        "targetDeviceIds": target_ids
    }
    print("📡 广播...")
    r = http_post('/apk/broadcast', payload)
    if r.get('ok'):
        f = r.get('filter', {})
        print(f"✅ 已广播给 {r.get('sent', 0)} 台设备 (fileId: {file_id})")
        if f.get('platform'):
            print(f"  平台过滤: {f['platform']}")
        if f.get('targetDeviceIds'):
            print(f"  定向设备: {len(f['targetDeviceIds'])} 台")
    else:
        print(f"❌ 广播失败: {r}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    if sys.argv[1] == '--list':
        users = list_devices()
        if users:
            query_versions(users)
        return

    apk_path = sys.argv[1]
    platform = None
    target = None
    all_devices = False

    if '--platform' in sys.argv:
        idx = sys.argv.index('--platform')
        if idx + 1 < len(sys.argv):
            platform = sys.argv[idx + 1].lower()
    if '--target' in sys.argv:
        idx = sys.argv.index('--target')
        if idx + 1 < len(sys.argv):
            target = sys.argv[idx + 1]
    if '--all' in sys.argv:
        all_devices = True

    push_update(apk_path, platform, target, all_devices)


if __name__ == '__main__':
    main()