#!/usr/bin/env python3
"""Read-only PMIC telemetry collector for the host UART."""

import argparse
import json
import os
import re
import signal
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path


STATUS_PATH = Path("/run/roboparty/pmic-status.json")
REQUIRED = ("CHRG_SN", "FW_VER", "CHRG_V", "CHRG_I", "BAT_V", "CHG_EN")
UID_RE = re.compile(r"[0-9A-F]{24}\Z")
VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[a-z0-9-]+)?\Z")
NUMBER_RE = re.compile(r"[0-9]+(?:\.[0-9]+)?\Z")


def env_file(path):
    values = {}
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return values
    for line in lines:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip("\"'")
    return values


def check_forward_conflict(port, config_path="/etc/default/bms_daemon"):
    config = env_file(config_path)
    enabled = config.get("FORWARD_ENABLE", "0").lower() not in ("0", "false", "no", "off")
    destination = config.get("FORWARD_PORT_B", "/dev/ttyS7")
    if enabled and os.path.realpath(port) == os.path.realpath(destination):
        raise RuntimeError(
            f"{port} is the BMS forward destination; disable FORWARD_ENABLE "
            "in /etc/default/bms_daemon before using it for PMIC queries"
        )


def check_port_owner(port):
    device = os.stat(port)
    if not os.path.exists("/proc"):
        return
    for process in Path("/proc").iterdir():
        if not process.name.isdigit() or int(process.name) == os.getpid():
            continue
        try:
            for fd in (process / "fd").iterdir():
                try:
                    owner = fd.stat()
                except (FileNotFoundError, PermissionError):
                    continue
                if owner.st_rdev == device.st_rdev and owner.st_ino == device.st_ino:
                    raise RuntimeError(f"{port} is already open by PID {process.name}")
        except (FileNotFoundError, PermissionError):
            continue


def decimal(field, suffix):
    if not field.endswith(suffix) or not NUMBER_RE.fullmatch(field[:-len(suffix)]):
        raise ValueError(f"invalid PMIC measurement: {field!r}")
    return float(field[:-len(suffix)])


def parse_reply(data):
    if len(data) > 1024:
        raise ValueError("PMIC reply too long")
    try:
        reply = data.decode("ascii")
    except UnicodeDecodeError as exc:
        raise ValueError("non-ASCII PMIC reply") from exc
    start = reply.find("CHRG_SN:")
    if start < 0:
        raise ValueError("missing CHRG_SN frame start")
    fields = {}
    for item in reply[start:].split(";"):
        if not item:
            continue
        if ":" not in item:
            raise ValueError(f"malformed PMIC field: {item!r}")
        key, value = item.split(":", 1)
        if key in fields:
            raise ValueError(f"duplicate PMIC field: {key}")
        fields[key] = value
    missing = set(REQUIRED) - fields.keys()
    if missing:
        raise ValueError(f"incomplete PMIC reply: {sorted(missing)}")
    if not UID_RE.fullmatch(fields["CHRG_SN"]):
        raise ValueError("invalid chip UID")
    if not VERSION_RE.fullmatch(fields["FW_VER"]):
        raise ValueError("invalid firmware version")
    if fields["CHG_EN"] not in ("0", "1"):
        raise ValueError("invalid CHG_EN")
    fault = fields.get("CHG_FAULT")
    if fault not in (None, "0", "1"):
        raise ValueError("invalid CHG_FAULT")
    input_v = decimal(fields["CHRG_V"], "V")
    current_a = decimal(fields["CHRG_I"], "A")
    battery_v = decimal(fields["BAT_V"], "V")
    enabled = fields["CHG_EN"] == "1"
    if fault == "1":
        state = "fault"
    elif enabled and current_a >= 0.2:
        state = "charging"
    elif enabled:
        state = "enabled_no_current"
    elif input_v < 16.0:
        state = "no_pd_input"
    else:
        state = "idle"
    return {
        "uid": fields["CHRG_SN"],
        "firmware_version": fields["FW_VER"],
        "input_voltage_v": input_v,
        "charge_current_a": current_a,
        "battery_voltage_v": battery_v,
        "charge_enabled": enabled,
        "charge_state": state,
        "mcu_fault": None if fault is None else fault == "1",
    }


def query(port, timeout):
    port.reset_input_buffer()
    port.write(b"CHRG_INFO:1;")
    port.flush()
    deadline = time.monotonic() + timeout
    received = bytearray()
    while time.monotonic() < deadline:
        part = port.read(128)
        if part:
            received.extend(part)
            if len(received) > 1024:
                raise ValueError("PMIC reply too long")
            if b"CHG_EN:" in received and b";" in received.split(b"CHG_EN:", 1)[1]:
                return parse_reply(received)
    raise TimeoutError(f"incomplete PMIC response: {bytes(received[-100:])!r}")


def publish(path, status):
    path.parent.mkdir(parents=True, exist_ok=True)
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=".pmic-status-", delete=False) as out:
            name = out.name
            json.dump(status, out, sort_keys=True)
            out.write("\n")
        os.chmod(name, 0o644)
        os.replace(name, path)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)


def status_at(port, data=None, error=None):
    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "port": port,
        "connected": error is None,
        "communication_fault": error,
        **(data or {key: None for key in (
            "uid", "firmware_version", "input_voltage_v", "charge_current_a",
            "battery_voltage_v", "charge_enabled", "charge_state", "mcu_fault")}),
    }


def run(args):
    import serial

    stopped = False

    def stop(_signal, _frame):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    while not stopped:
        try:
            check_forward_conflict(args.port, args.bms_config)
            check_port_owner(args.port)
            with serial.Serial(args.port, 115200, timeout=0.05,
                               write_timeout=args.timeout, exclusive=True) as device:
                while not stopped:
                    check_forward_conflict(args.port, args.bms_config)
                    data = query(device, args.timeout)
                    status = status_at(args.port, data=data)
                    publish(args.status_file, status)
                    print(json.dumps(status, sort_keys=True), flush=True)
                    if args.once:
                        return 0
                    time.sleep(args.interval)
        except (OSError, ValueError, TimeoutError, RuntimeError, serial.SerialException) as exc:
            status = status_at(args.port, error=str(exc))
            publish(args.status_file, status)
            print(json.dumps(status, sort_keys=True), file=sys.stderr, flush=True)
            if args.once:
                return 1
            time.sleep(args.interval)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default=os.getenv("PMIC_PORT", ""))
    parser.add_argument("--interval", type=float, default=5.0)
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--status-file", type=Path, default=STATUS_PATH)
    parser.add_argument("--bms-config", default="/etc/default/bms_daemon")
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args(argv)
    if not args.port or args.interval <= 0 or args.timeout <= 0:
        parser.error("a PMIC --port and positive interval/timeout are required")
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
