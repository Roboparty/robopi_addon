import importlib.util
import pathlib
import socket
import tempfile
import threading
import time
import unittest

spec = importlib.util.spec_from_file_location('bms_gpio', pathlib.Path(__file__).resolve().parents[1] / 'scripts/robopi-bms-gpio.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class FakeOutputs:
    def __init__(self):
        self.level = 0
        self.levels = [0, 0]
        self.events = []

    def set(self, level, reason):
        self.set_levels(level, level, reason)

    def set_levels(self, b0, c2, reason):
        for index, value in enumerate((b0, c2)):
            if value is not None:
                self.levels[index] = value
        self.level = self.levels[0]
        self.events.append((tuple(self.levels), reason))


def packet(io, power=1):
    return mod.FRAME.pack(*([53.2, 0., 20., 1., 1., 1., 1.] + [0, 0, 4., 4., b'', 8, 1, 100, 1, io, power]))


class TestBms(unittest.TestCase):
    def test_states(self):
        out = FakeOutputs()
        mod.apply_frame(packet(0x10000a), out)
        self.assertEqual(out.levels, [1, 0])
        out.set(1, 'disconnect')
        mod.apply_frame(packet(0x10000a), out)
        self.assertEqual(out.levels, [1, 0])
        mod.apply_frame(packet(0x10000f), out)
        self.assertEqual(out.levels, [1, 0])
        out.set(1, 'disconnect')
        mod.apply_frame(packet(0, 0), out)
        self.assertEqual(out.levels, [1, 0])
        mod.apply_frame(packet(0x100000, 0), out)
        self.assertEqual(out.level, 0)
        mod.apply_frame(packet(0x10000f), out)
        self.assertEqual(out.levels, [1, 0])
        mod.apply_frame(packet(0x100001), out)
        self.assertEqual(out.levels, [1, 0])
        mod.apply_frame(packet(0x100000, 0), out)
        mod.apply_frame(packet(0x100001), out)
        mod.apply_frame(packet(0, 0), out)
        self.assertEqual(out.levels, [0, 0])
        with self.assertRaises(ValueError):
            mod.apply_frame(packet(0, 255), out)

    def test_abi(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'bms.hpp'
            path.write_text('#pragma pack(push, 1)\nstruct BatteryStatus {' + mod.FIELDS + '};')
            mod.validate_header(path)
            path.write_text('struct BatteryStatus { double voltage; };')
            with self.assertRaises(RuntimeError):
                mod.validate_header(path)

    def test_stream_and_no_timeout(self):
        with tempfile.TemporaryDirectory() as folder:
            path = str(pathlib.Path(folder) / 'bms.sock')
            out, stop = FakeOutputs(), threading.Event()
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            server.bind(path)
            server.listen(1)
            server.settimeout(3)
            worker = threading.Thread(target=mod.monitor, args=(path, out, stop.is_set, .05, .05))
            worker.start()
            conn, _ = server.accept()
            try:
                # More than 5s with a live socket MUST NOT be a disconnect.
                time.sleep(5.2)
                self.assertEqual(out.events, [])
                frame = packet(0x100000, 0)
                conn.sendall(frame[:63])
                time.sleep(.15)
                self.assertEqual(out.events, [])
                conn.sendall(frame[63:] + packet(0x10000a))
                time.sleep(.15)
                self.assertEqual(out.levels, [1, 0])
                self.assertEqual(len(out.events), 2)
                conn.close()
                deadline = time.monotonic() + 2
                while out.levels != [1, 1] and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertEqual(out.levels, [1, 1])
                conn, _ = server.accept()
                conn.sendall(packet(0x10000a))
                time.sleep(.15)
                self.assertEqual(out.levels, [1, 0])
                conn.sendall(packet(0, 0))
                time.sleep(.15)
                self.assertEqual(out.levels, [1, 0])
                conn.sendall(packet(0x100000, 0))
                time.sleep(.15)
                self.assertEqual(out.level, 0)
            finally:
                stop.set()
                worker.join(2)
                conn.close()
                server.close()
            self.assertFalse(worker.is_alive())

    def test_connection_failure(self):
        out, stop = FakeOutputs(), threading.Event()
        with tempfile.TemporaryDirectory() as folder:
            path = str(pathlib.Path(folder) / 'absent')
            worker = threading.Thread(target=mod.monitor, args=(path, out, stop.is_set, .05, .05))
            worker.start()
            time.sleep(.15)
            stop.set()
            worker.join(2)
            self.assertEqual(out.level, 1)


if __name__ == '__main__':
    unittest.main()
