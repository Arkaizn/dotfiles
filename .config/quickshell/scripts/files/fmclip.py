#!/usr/bin/env python3
"""Puts files on the clipboard the way other file managers read them (filesd's
"clipSet" starts it): one owner offering several types at once, which wl-copy
can't (one type per call). Speaks the Wayland wire protocol directly
(ext_data_control_v1, or zwlr_data_control_v1 on Hyprland / older niri) —
standard library only.

    python3 -I fmclip.py < {"types": {"<mime>": "<text>", ...}}     (JSON on stdin)

Stays until another client takes the clipboard (or it's killed), then exits.
The data never goes through argv or a file.
"""
import array
import json
import os
import socket
import struct
import sys

MANAGERS = ("ext_data_control_manager_v1", "zwlr_data_control_manager_v1")
MAX_INPUT = 16 << 20


class Wl:
    def __init__(self):
        rt, disp = os.environ.get("XDG_RUNTIME_DIR"), os.environ.get("WAYLAND_DISPLAY", "wayland-0")
        path = disp if disp.startswith("/") else os.path.join(rt or "", disp)
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(path)
        self.next_id = 2
        self.globals = {}
        self.buf = b""
        self.fds = []

    def new(self):
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj, op, payload=b""):
        self.s.sendall(struct.pack("<II", obj, ((8 + len(payload)) << 16) | op) + payload)

    @staticmethod
    def string(t):
        b = t.encode() + b"\0"
        return struct.pack("<I", len(b)) + b + b"\0" * ((4 - len(b) % 4) % 4)

    @staticmethod
    def unstring(body, at):
        n = struct.unpack("<I", body[at:at + 4])[0]
        s = body[at + 4:at + 4 + n - 1].decode("utf-8", "replace")
        return s, at + 4 + n + ((4 - n % 4) % 4)

    def read(self):
        """the next event (obj, op, body); fds that came along queue up in self.fds"""
        while True:
            if len(self.buf) >= 8:
                obj, so = struct.unpack("<II", self.buf[:8])
                size = so >> 16
                if len(self.buf) >= size:
                    body = self.buf[8:size]
                    self.buf = self.buf[size:]
                    return obj, so & 0xffff, body
            data, anc, _, _ = self.s.recvmsg(65536, socket.CMSG_SPACE(16 * 4))
            if not data:
                raise EOFError
            for level, kind, raw in anc:
                if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                    a = array.array("i")
                    a.frombytes(raw[:len(raw) - len(raw) % a.itemsize])
                    self.fds.extend(a)
            self.buf += data

    def roundtrip(self, registry=None):
        cb = self.new()
        self.send(1, 0, struct.pack("<I", cb))           # wl_display.sync
        while True:
            obj, op, body = self.read()
            if registry is not None and obj == registry and op == 0:      # global(name, interface, version)
                name = struct.unpack("<I", body[:4])[0]
                iface, at = self.unstring(body, 4)
                self.globals[iface] = (name, struct.unpack("<I", body[at:at + 4])[0])
            elif obj == 1 and op == 0:
                raise RuntimeError("wayland error")
            elif obj == cb:
                return

    def bind(self, registry, iface, ver):
        name, have = self.globals[iface]
        i = self.new()
        self.send(registry, 0, struct.pack("<I", name) + self.string(iface) + struct.pack("<II", min(ver, have), i))
        return i


def main():
    raw = sys.stdin.buffer.read(MAX_INPUT + 1)
    if len(raw) > MAX_INPUT:
        sys.exit("fmclip: too much data")
    types = json.loads(raw).get("types") or {}
    data = {k: v.encode("utf-8", "surrogateescape") for k, v in types.items() if isinstance(k, str) and isinstance(v, str)}
    if not data:
        sys.exit("fmclip: nothing to offer")

    wl = Wl()
    registry = wl.new()
    wl.send(1, 1, struct.pack("<I", registry))           # wl_display.get_registry
    wl.roundtrip(registry)
    manager = next((m for m in MANAGERS if m in wl.globals), None)
    if manager is None or "wl_seat" not in wl.globals:
        sys.exit("fmclip: the compositor has no data-control protocol")
    seat = wl.bind(registry, "wl_seat", 1)
    mgr = wl.bind(registry, manager, 1)
    # both protocols: manager create_data_source = 0, get_data_device = 1;
    # source offer = 0, events send(mime, fd) = 0, cancelled = 1; device set_selection = 0
    source = wl.new()
    wl.send(mgr, 0, struct.pack("<I", source))
    for mime in data:
        wl.send(source, 0, wl.string(mime))
    device = wl.new()
    wl.send(mgr, 1, struct.pack("<II", device, seat))
    wl.send(device, 0, struct.pack("<I", source))
    wl.roundtrip()
    # the clipboard is ours: serve whoever pastes, until someone else takes it
    try:
        os.close(0)
    except OSError:
        pass
    while True:
        obj, op, body = wl.read()
        if obj == source and op == 0:
            mime, _ = wl.unstring(body, 0)
            fd = wl.fds.pop(0) if wl.fds else -1
            if fd >= 0:
                try:
                    payload = data.get(mime, b"")
                    while payload:
                        payload = payload[os.write(fd, payload):]
                except OSError:
                    pass                             # the reader went away
                finally:
                    os.close(fd)
        elif obj == source and op == 1:
            return 0
        elif obj == 1 and op == 0:
            return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (EOFError, ConnectionError, KeyboardInterrupt):
        sys.exit(0)
