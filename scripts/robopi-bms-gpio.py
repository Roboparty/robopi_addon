#!/usr/bin/python3
"""Read-only TWS socket client; exclusively control the two battery LED outputs."""
import argparse
import contextlib
import fcntl
import math
import os
import re
import signal
import socket
import struct
import time

# Packed BatteryStatus ABI deployed on RoboPi (little endian, 126 bytes).
# The older 121-byte ABI has the same package version and is NOT compatible.
FRAME = struct.Struct('<7dIH2d33sHHHIIB')
FIELDS = ('double voltage; double current; double temperature; double percentage; '
          'double charge; double capacity; double design_capacity; '
          'uint32_t protect_status; uint16_t work_state; double max_cell_voltage; '
          'double min_cell_voltage; char serial_number[33]; uint16_t sw_version; '
          'uint16_t hw_version; uint16_t soh; uint32_t cycles; '
          'uint32_t io_state; uint8_t power_on;')


def validate_header(path):
    with open(path, encoding='utf-8') as src:
        text = src.read()
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
    found = re.search(r'struct\s+BatteryStatus\s*\{([^}]+)\}', text)
    normalize = lambda s: re.sub(r'\s+', '', s)
    if (not found or normalize(found[1]) != normalize(FIELDS)
            or '#pragmapack(push,1)' not in normalize(text)):
        raise RuntimeError('Unsupported BMS ABI: need packed 126-byte BatteryStatus with io_state/power_on')


class Outputs:
    def __init__(self, paths):
        self.fds = []
        self.levels = [None, None]
        try:
            for path in paths:
                self.fds.append(os.open(path, os.O_WRONLY | os.O_CLOEXEC))
        except BaseException:
            self.close()
            raise

    def set(self, level, reason):
        self.set_levels(level, level, reason)

    def set_levels(self, b0, c2, reason):
        # Reassert on each event: sysfs LED files cannot enforce exclusive ownership.
        for index, (fd, level) in enumerate(zip(self.fds, (b0, c2))):
            if level is None:
                continue  # Unknown BMS state: preserve this output.
            os.lseek(fd, 0, os.SEEK_SET)
            if os.write(fd, b'1\n' if level else b'0\n') != 2:
                raise OSError('Short GPIO brightness write')
            if level != self.levels[index]:
                pin = ('GPIO1_B0', 'GPIO0_C2')[index]
                print(f'{pin}={level}: {reason}', flush=True)
            self.levels[index] = level

    def close(self):
        # Closing sysfs descriptors does not change the latched output.
        for fd in self.fds:
            os.close(fd)
        self.fds = []


def apply_frame(frame, outputs):
    values = FRAME.unpack(frame)
    if values[-1] not in (0, 1) or not all(math.isfinite(x) for x in values[:7]):
        raise ValueError('Invalid BatteryStatus frame; GPIO unchanged')
    io_state, power_on = values[-2:]
    b0 = 1 if io_state in (0x0010000A, 0x0010000F) else (0 if io_state == 0x00100000 else None)
    outputs.set_levels(b0, 0, f'valid battery data io_state=0x{io_state:08X}')
    return io_state, power_on


def monitor(path, outputs, stopping, retry=1.0, poll=0.5):
    last_status = None
    while not stopping():
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(poll)
            try:
                client.connect(path)
            except socket.timeout:
                # Timeout is NOT proof of disconnection and must not change GPIO.
                time.sleep(retry)
                continue
            except OSError as exc:
                outputs.set(1, f'socket connection failed: {exc}')
                time.sleep(retry)
                continue
            print(f'Connected: {path}; waiting for complete frames', flush=True)
            pending = b''
            while not stopping():
                try:
                    part = client.recv(FRAME.size - len(pending))
                except socket.timeout:
                    continue  # No stale-data timeout policy, as explicitly requested.
                except OSError as exc:
                    outputs.set(1, f'socket receive failed: {exc}')
                    break
                if not part:
                    outputs.set(1, 'socket EOF/disconnected')
                    break
                pending += part
                if len(pending) == FRAME.size:
                    try:
                        status = apply_frame(pending, outputs)
                    except ValueError as exc:
                        print(str(exc), flush=True)
                    else:
                        if status != last_status:
                            print(f'io_state=0x{status[0]:08X} power_on={status[1]}', flush=True)
                            last_status = status
                    pending = b''
        if not stopping():
            time.sleep(retry)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', default='/tmp/bms.sock')
    parser.add_argument('--header', default='/opt/roboparty/include/bms_driver.hpp')
    parser.add_argument('--out1', default='/sys/class/leds/dual_battery_b0/brightness')
    parser.add_argument('--out2', default='/sys/class/leds/dual_battery_c2/brightness')
    parser.add_argument('--check', action='store_true', help='validate ABI and paths without GPIO writes')
    args = parser.parse_args()
    validate_header(args.header)
    for path in (args.out1, args.out2):
        if not os.path.exists(path):
            raise RuntimeError(f'Missing output: {path}')
    if args.check:
        print('ABI=126 bytes; both output paths exist; no GPIO writes performed')
        return
    os.makedirs('/run/roboparty', exist_ok=True)
    with open('/run/roboparty/bms-gpio.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        stopped = False

        def stop(_sig, _frame):
            nonlocal stopped
            stopped = True

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        with contextlib.closing(Outputs((args.out1, args.out2))) as outputs:
            outputs.set_levels(1, 0, 'startup: B0 high until explicit battery-off state')
            monitor(args.socket, outputs, lambda: stopped)


if __name__ == '__main__':
    main()
