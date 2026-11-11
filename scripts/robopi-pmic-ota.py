#!/usr/bin/env python3
"""Inspect a PMIC, validate a firmware bundle, or manually update STM32."""

import argparse
import hashlib
import json
import os
import re
import struct
import sys
import time
import zlib
from pathlib import Path


TARGETS = {
    "stm32f103c8": {
        "board": "stm32f103_pmic",
        "app_file": "ChargeBAT.bin",
        "app_start": 0x08001000,
        "app_end": 0x0800FC00,
        "ram_end": 0x20005000,
        "ota_supported": True,
    },
    "gd32f503vet6": {
        "board": "gd32f503_pmic",
        "app_file": "ChargeBAT_GD32.bin",
        "app_start": 0x08008000,
        "app_end": 0x08040000,
        "ram_end": 0x20010000,
        "ota_supported": True,
    },
}
UID_RE = re.compile(r"^[0-9A-F]{24}$")


def load_bundle(path):
    manifest_path = Path(path).resolve()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    target_name = manifest.get("target")
    target = TARGETS.get(target_name) if isinstance(target_name, str) else None
    if (manifest.get("schema") != 2 or target is None or
            manifest.get("board") != target["board"] or
            manifest.get("ota_supported") is not target["ota_supported"]):
        raise ValueError("unsupported PMIC bundle")
    if (manifest.get("release_status") != "engineering-candidate" or
            not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+",
                             manifest.get("source_release", "")) or
            not re.fullmatch(r"[0-9a-f]{40}",
                             manifest.get("source_commit", ""))):
        raise ValueError("invalid PMIC release metadata")
    if target_name == "gd32f503vet6" and manifest.get("charging_enabled") is not False:
        raise ValueError("unverified GD32 charging must be disabled")
    version = manifest.get("version", "")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[a-z0-9-]+)?", version):
        raise ValueError("invalid firmware version")

    images = {}
    for name, address in (("boot", 0x08000000), ("app", target["app_start"])):
        item = manifest["images"][name]
        filename = "boot.bin" if name == "boot" else target["app_file"]
        if item["file"] != filename or int(item["load_address"], 16) != address:
            raise ValueError(f"invalid {name} image metadata")
        data = (manifest_path.parent / filename).read_bytes()
        if hashlib.sha256(data).hexdigest() != item["sha256"]:
            raise ValueError(f"{filename}: SHA-256 mismatch")
        images[name] = data

    app = images["app"]
    if not 8 <= len(app) <= target["app_end"] - target["app_start"]:
        raise ValueError("application is outside the PMIC flash partition")
    stack, reset = struct.unpack_from("<II", app)
    if not 0x20000000 < stack <= target["ram_end"] or stack & 7:
        raise ValueError("invalid initial stack pointer")
    if not (reset & 1 and
            target["app_start"] <= (reset & ~1) < target["app_start"] + len(app)):
        raise ValueError("invalid application reset vector")
    if version.encode("ascii") not in app:
        raise ValueError("manifest version is absent from application image")
    if not 8 <= len(images["boot"]) <= target["app_start"] - 0x08000000:
        raise ValueError("bootloader is outside its flash partition")
    boot_stack, boot_reset = struct.unpack_from("<II", images["boot"])
    if not (0x20000000 < boot_stack <= target["ram_end"] and
            boot_stack & 7 == 0 and boot_reset & 1 and
            0x08000000 <= (boot_reset & ~1) < 0x08000000 + len(images["boot"])):
        raise ValueError("invalid bootloader vectors")
    return manifest, images


def read_field(port, prefix, timeout):
    deadline = time.monotonic() + timeout
    received = bytearray()
    key = prefix.encode("ascii")
    while time.monotonic() < deadline:
        part = port.read(1)
        if part:
            received.extend(part)
            start = received.find(key)
            if start >= 0:
                end = received.find(b";", start)
                if end >= 0:
                    return received[start:end + 1].decode("ascii")
            if len(received) > 4096:
                del received[:2048]
    raise TimeoutError(f"no {prefix} reply; received {received[-128:]!r}")


def query(port, command, prefix, timeout, attempts=3):
    for attempt in range(attempts):
        port.reset_input_buffer()
        port.write(command.encode("ascii"))
        port.flush()
        try:
            return read_field(port, prefix, timeout)
        except TimeoutError:
            if attempt + 1 == attempts:
                raise


def identity(port, timeout):
    sn = query(port, "SN_GET:1;", "CHRG_SN:", timeout).split(":", 1)[1][:-1]
    version = query(port, "FW_VER:1;", "FW_VER:", timeout).split(":", 1)[1][:-1]
    if not UID_RE.fullmatch(sn):
        raise ValueError(f"invalid chip UID: {sn!r}")
    return sn, version


def check_bms_forward(port):
    config = Path("/etc/default/bms_daemon")
    try:
        entries = dict(line.strip().split("=", 1) for line in
                       config.read_text(encoding="utf-8").splitlines()
                       if "=" in line and not line.lstrip().startswith("#"))
    except FileNotFoundError:
        return
    enabled = entries.get("FORWARD_ENABLE", "0").lower() not in ("0", "false", "no", "off")
    destination = entries.get("FORWARD_PORT_B", "/dev/ttyS7").strip("\"'")
    if enabled and os.path.realpath(port) == os.path.realpath(destination):
        raise RuntimeError(f"{port} is the active BMS forwarding destination")


def send_ota_command(port, command, expected, timeout):
    port.write(command.encode("ascii"))
    port.flush()
    answer = read_field(port, expected.split(":", 1)[0] + ":"
                        if expected.startswith("OTA_ACK:") else expected, timeout)
    if answer != expected:
        raise RuntimeError(f"expected {expected!r}, got {answer!r}")


def flash_stm32(port, image, timeout, uid, recover=False):
    target = TARGETS["stm32f103c8"]
    if not 8 <= len(image) <= target["app_end"] - target["app_start"]:
        raise ValueError("STM32 application exceeds its Flash region")
    sp, reset = struct.unpack_from("<II", image)
    if not (0x20000000 < sp <= target["ram_end"] and sp & 7 == 0 and
            reset & 1 and target["app_start"] <= (reset & ~1) <
            target["app_start"] + len(image)):
        raise ValueError("STM32 image vectors or link address are invalid")
    if recover:
        query(port, "OTA_PING:1;", "OTA_BOOT:", timeout)
    else:
        found, version = identity(port, timeout)
        if found != uid:
            raise ValueError(f"UID mismatch: expected {uid}, got {found}")
        print(f"UID={found} old_version={version}")
        send_ota_command(port, "OTA_ENTER:1;", "OTA_BOOT;", timeout)
        query(port, "OTA_PING:1;", "OTA_BOOT:", timeout)

    crc = zlib.crc32(image) & 0xFFFFFFFF
    send_ota_command(port, f"OTA_BEGIN:{len(image)},{crc};", "OTA_READY;", timeout)
    for offset in range(0, len(image), 64):
        block = image[offset:offset + 64]
        send_ota_command(port, f"OTA_DATA:{offset},{block.hex()};",
                         f"OTA_ACK:{offset + len(block)};", timeout)
    send_ota_command(port, "OTA_END:1;", "OTA_DONE;", max(timeout, 10))
    print(f"STM32 OTA_DONE size={len(image)} crc32={crc:08X}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("inspect", "verify-bundle", "flash-stm32"))
    parser.add_argument("--port", help="PMIC host UART serial device for inspect")
    parser.add_argument("--bundle", help="manifest.json path for verify-bundle")
    parser.add_argument("--bin", type=Path, help="STM32 application image for flash-stm32")
    parser.add_argument("--uid", help="expected 24-digit STM32 chip UID")
    parser.add_argument("--recover", action="store_true", help="resume after interrupted STM32 update")
    parser.add_argument("--timeout", type=float, default=3)
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    if args.command == "verify-bundle":
        if not args.bundle:
            parser.error("verify-bundle requires --bundle")
        try:
            manifest, images = load_bundle(args.bundle)
        except (OSError, ValueError, KeyError, TypeError) as exc:
            print(f"PMIC bundle invalid: {exc}", file=sys.stderr)
            return 1
        print(f"target={manifest['target']} version={manifest['version']} "
              f"boot={len(images['boot'])} app={len(images['app'])}")
        return 0

    if not args.port:
        parser.error(f"{args.command} requires --port")
    if args.command == "flash-stm32" and (not args.bin or
            (not args.recover and not args.uid)):
        parser.error("flash-stm32 requires --bin and --uid (except with --recover)")
    if args.uid and not UID_RE.fullmatch(args.uid.upper()):
        parser.error("--uid must be 24 hexadecimal digits")
    try:
        import serial
    except ImportError as exc:
        parser.error(f"python3-serial is required: {exc}")
    try:
        if args.command == "flash-stm32":
            check_bms_forward(args.port)
            image = args.bin.read_bytes()
        with serial.Serial(args.port, 115200, timeout=0.05,
                           write_timeout=args.timeout, exclusive=True) as port:
            if args.command == "flash-stm32":
                flash_stm32(port, image, args.timeout,
                            args.uid.upper() if args.uid else None, args.recover)
            else:
                uid, version = identity(port, args.timeout)
                print(f"UID={uid} FW_VER={version}")
    except (OSError, ValueError, TimeoutError, RuntimeError, serial.SerialException) as exc:
        print(f"PMIC {args.command} failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
