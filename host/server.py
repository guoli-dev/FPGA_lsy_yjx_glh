import csv
import io
import json
import os
import queue
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

import car_link
from car_link import CarLink, available_ports
from protocol import (
    CAR_COLOR_NAMES,
    CAR_MODE_NAMES,
    ColorBlock,
    ColorPacket,
    MODE_NAMES,
    MotionBox,
    MotionPacket,
    StatusPacket,
)
from app import UdpWorker

INDEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html")


class ConsoleState:
    """UDP events -> JSON state. Replaces VisionConsole's UI-free half."""

    def __init__(self):
        self.lock = threading.Lock()
        self.started = time.monotonic()
        self.last_rx = 0.0
        self.last_color_rx = 0.0
        self.packet_count = 0
        self.alarm_count = 0
        self.ever_connected = False
        self.seen_color = False
        self.mode = None
        self.fps = None
        self.link = None
        self.frame_count = None
        self.latency = None
        self.motion_count = None
        self.blocks = []
        self.motion = None
        self.log = []
        self.alarms = {}
        self.focus = "全部"
        self.target_missing_since = None
        self.loss_seconds = 2.0
        self.min_fps = 20
        self.motion_limit = 200

        # 车端监控（模式 5，串口只读）
        self.car_status = "未连接"
        self.car_port = ""
        self.car = None
        self.car_frames = 0
        self.car_lost = 0
        self.car_seq_last = None
        self.car_stamps = []
        self.car_rate = 0

    # -- helpers below assume the caller holds self.lock ----------------------
    def _log(self, source, message):
        self.log.append((time.strftime("%H:%M:%S"), source, message))
        del self.log[:-200]

    def _alarm(self, key, active, message):
        if active and key not in self.alarms:
            self.alarms[key] = message
            self.alarm_count += 1
            self._log("告警", message)
        elif not active and key in self.alarms:
            del self.alarms[key]

    def handle(self, event):
        with self.lock:
            kind = event[0]
            if kind == "listening":
                self._log("系统", f"UDP {event[1]} 端口监听成功")
            elif kind == "invalid":
                self._log("系统", f"忽略未知数据帧：{event[1].hex(' ').upper()}")
            elif kind == "error":
                self._log("系统", event[1])
            elif kind == "packet":
                packet, received_at = event[1], event[3]
                self.last_rx = received_at
                self.ever_connected = True
                self.packet_count += 1
                if isinstance(packet, StatusPacket):
                    old = self.mode
                    self.mode = packet.mode
                    self.fps = packet.fps
                    self.link = packet.link
                    self.frame_count = packet.frame_count
                    self.latency = packet.latency_frames
                    self.motion_count = packet.motion_count
                    if old is not None and old != packet.mode:
                        self._log("FPGA", f"模式已切换为 {packet.mode} · {MODE_NAMES[packet.mode]}")
                elif isinstance(packet, ColorPacket):
                    self.blocks = [
                        {"name": b.name, "color": b.color, "detected": b.detected,
                         "center_x": b.center_x, "center_y": b.center_y,
                         "width": b.width, "deviation": b.deviation}
                        for b in packet.blocks
                    ]
                    self.last_color_rx = received_at
                    self.seen_color = True
                elif isinstance(packet, MotionPacket):
                    box = packet.box
                    self.motion = {"detected": box.detected, "left": box.left, "right": box.right,
                                   "top": box.top, "bottom": box.bottom,
                                   "motion_count": box.motion_count}
            elif kind == "car":
                packet, received_at = event[1], event[2]
                self.car = packet
                self.car_frames += 1
                self.car_stamps.append(received_at)
                if self.car_seq_last is not None:
                    self.car_lost += (packet.seq - self.car_seq_last - 1) & 0xFF
                self.car_seq_last = packet.seq
            elif kind == "car_status":
                self.car_status = event[1]
                if event[1] in ("串口已断开",) or event[1].startswith(("串口打开失败", "未安装 pyserial")):
                    self.car_port = ""

    def tick(self):
        now = time.monotonic()
        with self.lock:
            self.car_stamps = [stamp for stamp in self.car_stamps if now - stamp <= 1.0]
            self.car_rate = len(self.car_stamps)
            connected = self.ever_connected and (now - self.last_rx < 3.0)
            self._alarm("network", self.ever_connected and not connected, "网络通信中断超过 3 秒")
            self._alarm("fps", connected and self.min_fps > 0 and self.fps is not None
                        and self.fps < self.min_fps, f"视频帧率低于 {self.min_fps} FPS")
            self._alarm("motion", connected and self.motion_count is not None
                        and self.motion_count > self.motion_limit,
                        f"运动区域超过阈值 {self.motion_limit}")
            missing = False
            if self.seen_color and connected and self.blocks:
                if self.focus == "全部":
                    missing = not any(b["detected"] for b in self.blocks)
                else:
                    missing = not any(b["detected"] for b in self.blocks if b["name"] == self.focus)
            self.target_missing_since = now if missing and self.target_missing_since is None \
                else (None if not missing else self.target_missing_since)
            lost = self.target_missing_since is not None and now - self.target_missing_since >= self.loss_seconds
            self._alarm("target_lost", lost, f"{self.focus}目标连续丢失超过 {self.loss_seconds:g} 秒")

    def set_mode(self, mode):
        with self.lock:
            self.mode = mode
            self._log("上位机", f"请求切换到模式 {mode} · {MODE_NAMES[mode]}")

    def set_params(self, data):
        with self.lock:
            try:
                loss = float(data.get("loss_seconds", self.loss_seconds))
                min_fps = int(data.get("min_fps", self.min_fps))
                motion_limit = int(data.get("motion_limit", self.motion_limit))
                focus = str(data.get("focus", self.focus))
                if not 0.5 <= loss <= 60 or not 0 <= min_fps <= 240 or not 0 <= motion_limit <= 32767:
                    raise ValueError
                if focus not in ("全部", "红色", "绿色", "蓝色"):
                    raise ValueError
            except (TypeError, ValueError):
                return False
            self.loss_seconds = loss
            self.min_fps = min_fps
            self.motion_limit = motion_limit
            self.focus = focus
            self.target_missing_since = None
            self._log("上位机", "监控告警参数已应用")
            return True

    def _car_snapshot(self):
        data = {
            "status": self.car_status,
            "port": self.car_port,
            "pyserial": car_link.serial is not None,
            "rate": self.car_rate,
            "frames": self.car_frames,
            "lost": self.car_lost,
            "packet": None,
        }
        packet = self.car
        if packet is not None:
            heading = ((packet.heading + 180.0) % 360.0) - 180.0
            target = ((packet.target_angle + 180.0) % 360.0) - 180.0
            data["packet"] = {
                "seq": packet.seq,
                "mode": CAR_MODE_NAMES.get(packet.mode, "--"),
                "locked": CAR_COLOR_NAMES.get(packet.locked, "--"),
                "dev": packet.dev,
                "width": packet.width,
                "rgb": [
                    {"name": "红色", "dev": packet.dev_r, "wid": packet.wid_r},
                    {"name": "绿色", "dev": packet.dev_g, "wid": packet.wid_g},
                    {"name": "蓝色", "dev": packet.dev_b, "wid": packet.wid_b},
                ],
                "cmd": [packet.cmd_x, packet.cmd_y, packet.cmd_z],
                "wheels": list(packet.wheels),
                "vx": packet.vx,
                "vy": packet.vy,
                "heading": round(heading, 1),
                "target": round(target, 1),
                "gyro": packet.gyro_z,
                "battery": packet.battery,
                "uptime_ms": packet.uptime_ms,
                "flags": {
                    "imu": packet.imu_ready,
                    "zero_done": packet.zero_done,
                    "tracking": packet.tracking,
                    "arrived": packet.arrived,
                    "seen": packet.target_seen,
                    "stop": packet.stop_requested,
                },
            }
        return data

    def snapshot(self):
        with self.lock:
            now = time.monotonic()
            return {
                "connected": self.ever_connected and (now - self.last_rx < 3.0),
                "ever_connected": self.ever_connected,
                "mode": self.mode,
                "mode_name": MODE_NAMES.get(self.mode, "--") if self.mode is not None else "--",
                "fps": self.fps,
                "link": self.link,
                "frame_count": self.frame_count,
                "latency": self.latency,
                "motion_count": self.motion_count,
                "packet_count": self.packet_count,
                "alarm_count": self.alarm_count,
                "uptime": int(now - self.started),
                "blocks": self.blocks,
                "motion": self.motion,
                "focus": self.focus,
                "log": [{"time": t, "source": s, "message": m} for t, s, m in self.log],
                "alarms": [{"key": k, "message": v} for k, v in self.alarms.items()],
                "params": {"loss_seconds": self.loss_seconds,
                           "min_fps": self.min_fps, "motion_limit": self.motion_limit},
                "car": self._car_snapshot(),
            }


STATE = ConsoleState()
EVENTS = queue.Queue()
WORKER = UdpWorker(EVENTS)

CAR_LINK = None
CAR_LOCK = threading.Lock()


def car_ports_info():
    info = {"ports": [], "pyserial": car_link.serial is not None, "error": ""}
    if car_link.serial is None or car_link.list_ports is None:
        return info
    try:
        info["ports"] = available_ports()
    except Exception as exc:
        info["error"] = f"{type(exc).__name__}: {exc}"
    return info


def diag_info():
    import os
    import platform
    info = {
        "python": sys.executable,
        "version": platform.python_version(),
        "os": os.name,
        "cwd": os.getcwd(),
        "pyserial": car_link.serial is not None,
        "serial_version": getattr(car_link.serial, "__version__", None) if car_link.serial else None,
        "serial_file": getattr(car_link.serial, "__file__", None) if car_link.serial else None,
        "ports": [],
        "error": "",
    }
    if car_link.list_ports is not None:
        try:
            info["ports"] = [
                {"device": p.device, "description": p.description, "hwid": p.hwid}
                for p in car_link.list_ports.comports()
            ]
        except Exception as exc:
            info["error"] = f"{type(exc).__name__}: {exc}"
    return info


def car_connect(port: str):
    global CAR_LINK
    port = (port or "").strip()
    if not port:
        return False, "未选择串口"
    if car_link.serial is None:
        return False, "未安装 pyserial，请先执行 pip install pyserial"
    with CAR_LOCK:
        if CAR_LINK is not None:
            CAR_LINK.stop()
        CAR_LINK = CarLink(EVENTS, port)
        CAR_LINK.start()
    with STATE.lock:
        STATE.car_port = port
        STATE.car_status = f"正在打开 {port}"
        STATE._log("系统", f"打开车端串口 {port}")
    return True, ""


def car_disconnect():
    global CAR_LINK
    with CAR_LOCK:
        if CAR_LINK is not None:
            CAR_LINK.stop()
            CAR_LINK = None
    with STATE.lock:
        STATE.car_port = ""
        STATE.car_status = "串口已断开"
    return True


def process_loop():
    while True:
        try:
            STATE.handle(EVENTS.get(timeout=0.2))
        except queue.Empty:
            pass
        STATE.tick()


class Handler(BaseHTTPRequestHandler):
    def _send(self, body, code, ctype):
        body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code=200):
        self._send(json.dumps(obj, ensure_ascii=False), code, "application/json; charset=utf-8")

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            with open(INDEX, "rb") as f:
                self._send(f.read().decode("utf-8"), 200, "text/html; charset=utf-8")
        elif path == "/state":
            self._json(STATE.snapshot())
        elif path == "/car/ports":
            self._json(car_ports_info())
        elif path == "/diag":
            self._json(diag_info())
        elif path == "/export":
            buf = io.StringIO()
            w = csv.writer(buf)
            w.writerow(("时间", "类别", "内容"))
            for t, s, m in STATE.log:
                w.writerow((t, s, m))
            name = time.strftime("FPGA_log_%Y%m%d_%H%M%S.csv")
            self.send_response(200)
            self.send_header("Content-Type", "text/csv; charset=utf-8")
            self.send_header("Content-Disposition", f"attachment; filename={name}")
            body = buf.getvalue().encode("utf-8-sig")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        try:
            data = json.loads((self.rfile.read(length) or b"{}").decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            data = {}
        if path == "/mode":
            mode = int(data.get("mode", -1))
            if mode in MODE_NAMES:
                WORKER.set_mode(mode)
                STATE.set_mode(mode)
                self._json({"ok": True})
            else:
                self._json({"ok": False, "error": "bad mode"}, 400)
        elif path == "/params":
            self._json({"ok": STATE.set_params(data)})
        elif path == "/car/connect":
            ok, error = car_connect(str(data.get("port", "")))
            self._json({"ok": ok, "error": error}, 200 if ok else 400)
        elif path == "/car/disconnect":
            self._json({"ok": car_disconnect()})
        else:
            self._json({"error": "not found"}, 404)

    def log_message(self, *args):
        pass


def check():
    st = ConsoleState()
    st.handle(("packet", StatusPacket(3, 60, True, 12840, 2, 3, b""), ("x", 1), time.monotonic()))
    st.handle(("packet", ColorPacket(blocks=(
        ColorBlock("红色", "#ef4444", True, 10, 720, 160, 90),
        ColorBlock("绿色", "#22c55e", True, -10, 560, 403, 140),
        ColorBlock("蓝色", "#3b82f6", False, None, None, None, 0),
    ), raw=b""), ("x", 1), time.monotonic()))
    st.handle(("packet", MotionPacket(MotionBox(True, 400, 700, 200, 500, 3), b""), ("x", 1), time.monotonic()))
    snap = st.snapshot()
    assert snap["mode"] == 3 and snap["mode_name"] == "色块追踪"
    assert snap["blocks"][0]["center_x"] == 720
    assert snap["blocks"][2]["detected"] is False
    assert snap["motion"]["detected"] and snap["motion"]["motion_count"] == 3
    assert st.set_params({"loss_seconds": 1.5, "min_fps": 30, "motion_limit": 500, "focus": "红色"})
    assert snap["blocks"][0]["name"] == "红色"
    print("PASS: console state + snapshot")


def main():
    if "--check" in sys.argv:
        check()
        return
    port = 8000
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
    threading.Thread(target=process_loop, daemon=True).start()
    WORKER.start()
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"FPGA Vision 网页版已启动：http://localhost:{port}")
    print(f"脚本路径：{os.path.abspath(__file__)}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        WORKER.stop()
        car_disconnect()
        server.server_close()


if __name__ == "__main__":
    main()
