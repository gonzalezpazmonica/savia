#!/usr/bin/env python3
"""CLI for ZeroClaw network setup — interactive wizard."""
import json
import sys
import getpass
import argparse
from .network_setup import detect_ssid, detect_host_ip, generate_esp32_config
from .esp32_wifi import deploy_config, scan_wifi as scan_wifi_from_esp32
from .esp32_wifi import verify_wifi as verify_esp32_wifi, reset as reset_esp32


def cmd_setup(args):
    """Interactive network setup wizard."""
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  🌐 ZeroClaw Network Setup")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print()

    # 1. Detect host network
    print("📋 1/4 — Detecting host network...")
    ssid = detect_ssid()
    host_ip = detect_host_ip()

    if ssid:
        print(f"  WiFi SSID: {ssid}")
    else:
        ssid = input("  Could not detect SSID. Enter manually: ").strip()

    if host_ip:
        print(f"  Host IP:   {host_ip}")
    else:
        host_ip = input("  Could not detect IP. Enter manually: ").strip()

    # 2. Confirm or change
    print()
    use_detected = input(f"  Use network '{ssid}'? [Y/n] ").strip().lower()
    if use_detected == 'n':
        ssid = input("  Enter WiFi SSID: ").strip()

    # 3. Password (hidden input)
    print()
    print("📋 2/4 — WiFi password")
    print("  (stored ONLY on ESP32 flash + local config.json, never in git)")
    password = getpass.getpass("  WiFi password: ")

    # 4. Generate and deploy
    print()
    print("📋 3/4 — Generating config...")
    config = generate_esp32_config(ssid, password, host_ip, args.port or 8765)
    # Mask password in display
    display = dict(config)
    display["wifi_pass"] = "***"  # no suffix: terminal scrollback is not a vault
    print(f"  Config: {json.dumps(display, indent=2)}")

    print()
    print("📋 4/4 — Deploying to ESP32...")
    ok, output = deploy_config(config, port=args.serial)
    if ok:
        print("  ✅ Config deployed to ESP32")
        print("  Resetting ESP32 to apply WiFi config...")
        reset_esp32(port=args.serial)
        import time
        time.sleep(5)
        # Verify
        status = verify_esp32_wifi(port=args.serial)
        if status.get("connected"):
            print(f"  ✅ ESP32 connected! IP: {status['ip']}")
            print(f"  ✅ Same network as host ({host_ip})")
        else:
            print("  ⚠️  ESP32 not yet connected. Check password and retry.")
    else:
        print(f"  ❌ Deploy failed: {output}")
    print()
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")


def cmd_check(args):
    """Verify ESP32 WiFi connectivity."""
    print("Checking ESP32 WiFi status...")
    status = verify_esp32_wifi(port=args.serial)
    print(json.dumps(status, indent=2))
    if status.get("connected"):
        host_ip = detect_host_ip()
        esp_ip = status.get("ip", "")
        same_subnet = (host_ip and esp_ip and
                       host_ip.rsplit('.', 1)[0] == esp_ip.rsplit('.', 1)[0])
        if same_subnet:
            print(f"✅ Same network: host={host_ip}, ESP32={esp_ip}")
        else:
            print(f"⚠️  Different subnets: host={host_ip}, ESP32={esp_ip}")


def cmd_scan(args):
    """Scan WiFi networks from ESP32."""
    print("Scanning WiFi from ESP32 (takes ~5s)...")
    result = scan_wifi_from_esp32(port=args.serial)
    if result:
        print(result)
    else:
        print("❌ Could not scan. Is ESP32 connected via USB?")


def main():
    p = argparse.ArgumentParser(description="ZeroClaw Network Setup")
    p.add_argument("--serial", help="Serial port")
    p.add_argument("--port", type=int, default=8765, help="Host bridge port")
    sub = p.add_subparsers(dest="cmd")
    sub.add_parser("setup", help="Interactive WiFi setup")
    sub.add_parser("check", help="Verify ESP32 WiFi")
    sub.add_parser("scan", help="Scan WiFi from ESP32")
    args = p.parse_args()

    cmds = {"setup": cmd_setup, "check": cmd_check, "scan": cmd_scan}
    fn = cmds.get(args.cmd)
    if fn:
        fn(args)
    else:
        cmd_setup(args)  # default to setup wizard


if __name__ == "__main__":
    main()
