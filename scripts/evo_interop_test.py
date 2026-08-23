#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EVO 设备间通信测试（绕过系统代理直连 relay）"""
import json, time, urllib.request, os, sys

# 绕过系统代理（Hermes 环境有 HTTP_PROXY=127.0.0.1:7897）
for k in ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy']:
    os.environ.pop(k, None)

RELAY = 'https://relay.vios.top'
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'

def get(p):
    req = urllib.request.Request(RELAY + p, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())

def post(p, d):
    body = json.dumps(d).encode()
    req = urllib.request.Request(RELAY + p, data=body,
        headers={'User-Agent': UA, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())

def main():
    devices = get('/users').get('users', [])
    if len(devices) < 2:
        print(f"❌ 在线设备不足 ({len(devices)})，需至少 2 台")
        for d in devices: print(f"  {d['name']} {d['deviceId'][:8]}")
        return
    print("在线设备:")
    for d in devices:
        print(f"  {d['name']}  {d['deviceId'][:8]}")

    A, B = devices[0], devices[1]
    print(f"\n测试: {A['name']} → {B['name']} (ping)")

    # 1. A 发 ping 给 B
    r = post('/cmd', {'target': A['deviceId'], 'cmd': 'send_ping_test', 'target': B['deviceId']})
    req_id = r.get('requestId', '')
    print(f"① {A['name']} 发送 EVO-PING (req={req_id})")
    time.sleep(3)
    res = get(f'/cmd/result?requestId={req_id}')
    print(f"   → {A['name']} 发送结果: {json.dumps(res.get('result', res), ensure_ascii=False)[:200]}")

    # 2. A 查日志确认收到 B 回显
    time.sleep(2)
    r2 = post('/cmd', {'target': A['deviceId'], 'cmd': 'log'})
    req2 = r2.get('requestId', '')
    time.sleep(3)
    logs = get(f'/cmd/result?requestId={req2}')
    log_str = json.dumps(logs, ensure_ascii=False)
    has_echo = 'EVO-PING' in log_str or '互测' in log_str or '回显' in log_str
    print(f"② {A['name']} 日志确认回显: {'✅' if has_echo else '❌'}")
    print(f"   日志片段: {log_str[:300]}")

    # 3. 反向：B 发 ping 给 A
    r3 = post('/cmd', {'target': B['deviceId'], 'cmd': 'send_ping_test', 'target': A['deviceId']})
    req3 = r3.get('requestId', '')
    print(f"③ {B['name']} 发送 EVO-PING (req={req3})")
    time.sleep(3)
    res3 = get(f'/cmd/result?requestId={req3}')
    print(f"   → {B['name']} 发送结果: {json.dumps(res3.get('result', res3), ensure_ascii=False)[:200]}")

    print("\n测试完成")

if __name__ == '__main__':
    main()
