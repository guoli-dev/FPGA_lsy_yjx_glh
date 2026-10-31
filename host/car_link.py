"""小车遥测串口链路。

PC 端插一个逐飞无线串口模块（与车上那个配对），Windows 会虚拟出一个 COM 口。
本模块只负责读取、找帧、校验，解析结果放进既有的 events 队列，由 app 处理。

事件格式：
    ("car", CarTelemetry, received_at)
    ("car_status", "文本状态")
"""

import os
import sys
import threading
import time

# 随项目携带的 pyserial（vendor/serial），离线优先使用，免去 pip 安装
_VENDOR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor")
if os.path.isdir(_VENDOR) and _VENDOR not in sys.path:
    sys.path.insert(0, _VENDOR)

try:
    import serial
    from serial.tools import list_ports
except ImportError:  # 既没有 vendor 也没装 pyserial 时界面仍可运行，只是无法打开串口
    serial = None
    list_ports = None

from protocol import CAR_FRAME_LEN, CAR_HEADER, CAR_TAIL, crc8, parse_car_frame

BAUDRATE = 115200
_MAX_BUFFER = 4096


def available_ports() -> list[str]:
    if list_ports is None:
        return []
    return sorted(port.device for port in list_ports.comports())


class CarLink(threading.Thread):
    def __init__(self, events, port: str, baudrate: int = BAUDRATE):
        super().__init__(daemon=True)
        self.events = events
        self.port = port
        self.baudrate = baudrate
        self.running = threading.Event()
        self.running.set()
        self.handle = None

    def run(self):
        if serial is None:
            self.events.put(("car_status", "未安装 pyserial：请执行 pip install pyserial"))
            return
        try:
            self.handle = serial.Serial(self.port, self.baudrate, timeout=0.05)
        except Exception as exc:  # 串口被占用、拔掉、权限不足
            self.events.put(("car_status", f"串口打开失败：{exc}"))
            return

        self.events.put(("car_status", f"{self.port} 已连接"))
        buffer = bytearray()
        try:
            while self.running.is_set():
                chunk = self.handle.read(256)
                if chunk:
                    buffer.extend(chunk)
                    self._drain(buffer)
                elif len(buffer) > _MAX_BUFFER:
                    buffer.clear()
        except Exception as exc:
            if self.running.is_set():
                self.events.put(("car_status", f"串口读取中断：{exc}"))
        finally:
            try:
                if self.handle is not None:
                    self.handle.close()
            except Exception:
                pass
            self.events.put(("car_status", "串口已断开"))

    def _drain(self, buffer: bytearray):
        while True:
            start = buffer.find(CAR_HEADER)
            if start < 0:
                buffer.clear()
                return
            if start:
                del buffer[:start]
            if len(buffer) < 4:
                return
            if buffer[3] != CAR_FRAME_LEN:
                del buffer[0]
                continue
            if len(buffer) < CAR_FRAME_LEN:
                return

            frame = bytes(buffer[:CAR_FRAME_LEN])
            if frame[CAR_FRAME_LEN - 1] != CAR_TAIL or frame[40] != crc8(frame[:40]):
                del buffer[0]
                continue

            del buffer[:CAR_FRAME_LEN]
            packet = parse_car_frame(frame)
            if packet is not None:
                self.events.put(("car", packet, time.monotonic()))

    def stop(self):
        self.running.clear()
        try:
            if self.handle is not None:
                self.handle.close()
        except Exception:
            pass
