#!/usr/bin/python3
"""One-way UART bridge: bytes from PORT_A are written to PORT_B."""
import os
import select
import sys
import termios
import time

DEFAULT_PORT_A = '/dev/ttyS3'
DEFAULT_PORT_B = '/dev/ttyS7'
DEFAULT_BAUD = 115200
REOPEN_DELAY = 1.0
CHUNK = 4096

BAUD_MAP = {
    9600: termios.B9600,
    19200: termios.B19200,
    38400: termios.B38400,
    57600: termios.B57600,
    115200: termios.B115200,
    230400: termios.B230400,
    460800: termios.B460800,
    921600: termios.B921600,
}


def log(message):
    print(message, flush=True)


def env_int(name, default):
    raw = os.environ.get(name, '')
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        raise SystemExit(f'robopi-uart-bridge: invalid {name}={raw!r}')


def open_serial(path, baud):
    while not os.path.exists(path):
        log(f'waiting for {path}')
        time.sleep(REOPEN_DELAY)

    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = BAUD_MAP[baud]
    attrs[5] = BAUD_MAP[baud]
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


def pump(port_a, port_b):
    while True:
        readable, _, _ = select.select([port_a], [], [])
        if port_a not in readable:
            continue
        data = os.read(port_a, CHUNK)
        if not data:
            raise RuntimeError('source port returned EOF')
        view = memoryview(data)
        while view:
            try:
                written = os.write(port_b, view)
            except BlockingIOError:
                select.select([], [port_b], [])
                continue
            view = view[written:]


def main():
    port_a = os.environ.get('PORT_A', DEFAULT_PORT_A)
    port_b = os.environ.get('PORT_B', DEFAULT_PORT_B)
    baud = env_int('BAUD', DEFAULT_BAUD)
    if baud not in BAUD_MAP:
        raise SystemExit(f'robopi-uart-bridge: unsupported BAUD={baud}')

    fd_a = -1
    fd_b = -1
    log(f'bridging {port_a} -> {port_b} at {baud} baud')
    while True:
        try:
            if fd_a < 0:
                fd_a = open_serial(port_a, baud)
                log(f'opened source {port_a}')
            if fd_b < 0:
                fd_b = open_serial(port_b, baud)
                log(f'opened sink {port_b}')
            pump(fd_a, fd_b)
        except KeyboardInterrupt:
            log('stopping')
            return 0
        except OSError as exc:
            log(f'bridge error: {exc}; reopening in {REOPEN_DELAY}s')
            if fd_a >= 0:
                os.close(fd_a)
                fd_a = -1
            if fd_b >= 0:
                os.close(fd_b)
                fd_b = -1
            time.sleep(REOPEN_DELAY)


if __name__ == '__main__':
    sys.exit(main())
