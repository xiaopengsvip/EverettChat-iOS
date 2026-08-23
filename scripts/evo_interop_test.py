#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
EVO 设备间通信自动测试（从 Hermes 侧驱动，经 relay 远程命令）
用法:
  python evo_interop_test.py [--from DEVICE_ID] [--to DEVICE_ID] [--rounds N] [--mode text|ping|all]

测试流程:
  1. 列出 relay 在线设备
  2. 对每对设备: A 发 send_ping_test → B 收到 EVO-PING-xxx 自动回显
     → A 收到回显 (查 A 的日志/状态) = 双向通道验证
  3. 记录所有测试结果到 测试报告
"""
import json
import sys
import time
import urllib.request
import datetime

RELAY = "https://relay.vios.top"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

def http_get(path):
    req = urllib.request.Request(RELAY + path, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())

def http_post(path, data):
    body = json.dumps(data).encode()
    req = urllib.request.Request(RELAY + path, data=body,
        headers={"User-Agent": UA, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())

def get_online_devices():
    d = http_get("/users")
    return d.get("users", [])

def send_cmd(device_id, cmd, **extra):
    payload = {"target": device_id, "cmd": cmd, **extra}
    return http_post("/cmd", payload)

def wait_result(request_id, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = http_get(f"/cmd/result?requestId={request_id}")
            if r.get("status") == "done":
                return r.get("result")
            if r.get("status") == "unknown":
                return {"error": "device not responding / offline"}
        except Exception:
            pass
        time.sleep(1.5)
    return {"error": "timeout"}

def main():
    args = [a for a in sys.argv[1:]]
    mode = "ping"
    rounds = 1
    only_from = None
    only_to = None
    for a in args:
        if a.startswith("--mode="): mode = a.split("=")[1]
        elif a.startswith("--rounds="): rounds = int(a.split("=")[1])
        elif a.startswith("--from="): only_from = a.split("=")[1]
        elif a.startswith("--to="): only_to = a.split("=")[1]

    print("=" * 60)
    print(f"EVO 设备间通信测试  {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"模式: {mode}  轮次: {rounds}")
    print("=" * 60)

    devices = get_online_devices()
    if not devices:
        print("❌ 无在线设备！请先打开 App")
        return
    print(f"在线设备 ({len(devices)}):")
    for d in devices:
        print(f"  {d['name']}  {d['deviceId']}")
    print()

    # 构造测试对
    pairs = []
    if only_from and only_to:
        pairs = [(only_from, only_to)]
    else:
        for i in range(len(devices)):
            for j in range(len(devices)):
                if i != j:
                    pairs.append((devices[i]["deviceId"], devices[j]["deviceId"]))
        # 每对只测一次（无向）
        seen = set()
        pairs = [p for p in pairs if (p[0], p[1]) not in seen and not seen.add((p[1], p[0]))]
        pairs = pairs[:min(len(pairs), 4)]  # 最多 4 对

    results = []
    for rnd in range(1, rounds + 1):
        for (a, b) in pairs:
            name_a = next((d["name"] for d in devices if d["deviceId"] == a), a[:8])
            name_b = next((d["name"] for d in devices if d["deviceId"] == b), b[:8])
            print(f"\n--- 测试 {rnd}.{len(results)+1}: {name_a} → {name_b} ---")

            # 1. A 发 ping 测试消息
            r = send_cmd(a, "send_ping_test", target=b)
            req_id = r.get("requestId", "")
            if not r.get("ok"):
                print(f"❌ 命令发送失败: {r}")
                results.append({"from": name_a, "to": name_b, "ok": False, "err": "cmd send failed"})
                continue
            print(f"  ① {name_a} 发送 EVO-PING (req={req_id})")
            res = wait_result(req_id, timeout=15)
            sent_ok = "ping" in str(res) or "sent" in str(res)
            print(f"  → A 发送结果: {res}")

            # 2. B 应自动回显 → A 收到（查 A 日志确认）
            time.sleep(2)
            r2 = send_cmd(a, "log")
            req2 = r2.get("requestId", "")
            logs = wait_result(req2, timeout=15)
            log_str = json.dumps(logs, ensure_ascii=False)
            echo_ok = "EVO-PING" in log_str and "收到互测" in log_str
            print(f"  ② {name_a} 日志确认收到回显: {'✅' if echo_ok else '❌'}")
            if not echo_ok:
                # 也许日志被清，试 status
                print(f"  A 最近日志: {str(logs)[:200]}")

            ok = sent_ok and echo_ok
            results.append({
                "from": name_a, "to": name_b,
                "ok": ok,
                "sent": sent_ok, "echo": echo_ok,
                "detail": res
            })
            print(f"  → {'✅ 双向通道正常' if ok else '❌ 测试失败'}")

    # 汇总
    print("\n" + "=" * 60)
    print("测试汇总:")
    passed = sum(1 for r in results if r["ok"])
    print(f"  通过: {passed}/{len(results)}")
    for r in results:
        mark = "✅" if r["ok"] else "❌"
        print(f"  {mark} {r['from']} ↔ {r['to']}")
    print("=" * 60)

if __name__ == "__main__":
    main()
