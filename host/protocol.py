from dataclasses import dataclass


MODE_NAMES = {
    0: "原始画面",
    1: "边缘检测",
    2: "卡通化",
    3: "色块追踪",
    4: "运动检测",
}


@dataclass(frozen=True)
class StatusPacket:
    mode: int
    fps: int
    link: bool
    frame_count: int | None
    latency_frames: int | None
    motion_count: int | None
    raw: bytes


@dataclass(frozen=True)
class ColorBlock:
    name: str
    color: str
    detected: bool
    deviation: int | None
    center_x: int | None
    center_y: int | None
    width: int


@dataclass(frozen=True)
class ColorPacket:
    blocks: tuple[ColorBlock, ColorBlock, ColorBlock]
    raw: bytes


@dataclass(frozen=True)
class MotionBox:
    detected: bool
    left: int | None
    right: int | None
    top: int | None
    bottom: int | None
    motion_count: int


@dataclass(frozen=True)
class MotionPacket:
    box: MotionBox
    raw: bytes


def encode_mode(mode: int) -> bytes:
    if mode not in MODE_NAMES:
        raise ValueError("mode must be between 0 and 4")
    return bytes((0x01, mode))


def encode_status_request() -> bytes:
    return b"\x02"


def encode_color_request() -> bytes:
    return b"\x03"


def encode_motion_request() -> bytes:
    return b"\x04"


def _decode_block(
    name: str,
    color: str,
    dev_byte: int,
    width_byte: int,
    y_byte: int | None = None,
) -> ColorBlock:
    if dev_byte == 0x80:
        return ColorBlock(name, color, False, None, None, None, 0)
    deviation = dev_byte - 256 if dev_byte >= 128 else dev_byte
    center_x = max(0, min(1279, 640 + deviation * 8))
    center_y = None if y_byte is None else min(719, y_byte * 4)
    return ColorBlock(name, color, True, deviation, center_x, center_y, width_byte * 8)


def parse_packet(data: bytes) -> StatusPacket | ColorPacket | MotionPacket | None:
    if len(data) == 6 and data[0] == 0xAA and data[5] == 0x55:
        mode = data[1]
        if mode not in MODE_NAMES:
            return None
        return StatusPacket(
            mode=mode,
            fps=data[2] | (data[3] << 8),
            link=bool(data[4]),
            frame_count=None,
            latency_frames=None,
            motion_count=None,
            raw=data,
        )

    if len(data) == 12 and data[0] == 0xAA and data[11] == 0x55:
        mode = data[1]
        if mode not in MODE_NAMES:
            return None
        return StatusPacket(
            mode=mode,
            fps=data[2] | (data[3] << 8),
            link=bool(data[4]),
            frame_count=data[5] | (data[6] << 8),
            latency_frames=data[7] | (data[8] << 8),
            motion_count=data[9] | (data[10] << 8),
            raw=data,
        )

    # Ethernet telemetry frame: each color is deviation/8, width/8, center_y/4.
    if len(data) == 11 and data[0] == 0xAB and data[10] == 0x55:
        return ColorPacket(
            blocks=(
                _decode_block("红色", "#ef4444", data[1], data[2], data[3]),
                _decode_block("绿色", "#22c55e", data[4], data[5], data[6]),
                _decode_block("蓝色", "#3b82f6", data[7], data[8], data[9]),
            ),
            raw=data,
        )

    # Compact color frame mirrors the existing 7-byte UART packet in design_top_wrapper.v.
    if len(data) == 7 and data[0] == 0xAA:
        return ColorPacket(
            blocks=(
                _decode_block("红色", "#ef4444", data[1], data[2]),
                _decode_block("绿色", "#22c55e", data[3], data[4]),
                _decode_block("蓝色", "#3b82f6", data[5], data[6]),
            ),
            raw=data,
        )

    # Motion bounding-box telemetry: 0xAC + 8-byte box + 2-byte count + 0x55.
    # box bit layout (isp_top O_mot_box): [42]=valid [41:31]=left [30:20]=right
    # [19:10]=top [9:0]=bottom, coords in 1280x720.
    if len(data) == 12 and data[0] == 0xAC and data[11] == 0x55:
        box = int.from_bytes(data[1:9], "little")
        detected = bool((box >> 42) & 1)
        left = (box >> 31) & 0x7FF
        right = (box >> 20) & 0x7FF
        top = (box >> 10) & 0x3FF
        bottom = box & 0x3FF
        return MotionPacket(
            box=MotionBox(
                detected=detected,
                left=left if detected else None,
                right=right if detected else None,
                top=top if detected else None,
                bottom=bottom if detected else None,
                motion_count=data[9] | (data[10] << 8),
            ),
            raw=data,
        )

    return None


# ---------------------------------------------------------------------------
# 车端遥测（小车 → 逐飞无线串口 → PC），与 FPGA 的 UDP 协议完全独立
# 帧长 42 字节：C5 01 seq len flags mode locked dev wid
#              R_dev R_wid G_dev G_wid B_dev B_wid cmdX cmdY cmdZ
#              LF RF LB RB vx vy heading target gyro batt uptime crc8 5C
# ---------------------------------------------------------------------------

CAR_HEADER = 0xC5
CAR_TAIL = 0x5C
CAR_FRAME_LEN = 42

CAR_MODE_NAMES = {0: "自动", 1: "红", 2: "绿", 3: "蓝"}
CAR_COLOR_NAMES = {0: "无", 1: "红", 2: "绿", 3: "蓝"}


def crc8(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


@dataclass(frozen=True)
class CarTelemetry:
    seq: int
    flags: int
    mode: int
    locked: int
    dev: int | None
    width: int
    dev_r: int | None
    wid_r: int
    dev_g: int | None
    wid_g: int
    dev_b: int | None
    wid_b: int
    cmd_x: int
    cmd_y: int
    cmd_z: int
    wheels: tuple[int, int, int, int]
    vx: int
    vy: int
    heading: float
    target_angle: float
    gyro_z: float
    battery: float
    uptime_ms: int
    raw: bytes

    @property
    def imu_ready(self) -> bool:
        return bool(self.flags & 0x01)

    @property
    def zero_done(self) -> bool:
        return bool(self.flags & 0x02)

    @property
    def tracking(self) -> bool:
        return bool(self.flags & 0x04)

    @property
    def arrived(self) -> bool:
        return bool(self.flags & 0x08)

    @property
    def target_seen(self) -> bool:
        return bool(self.flags & 0x10)

    @property
    def locked_active(self) -> bool:
        return bool(self.flags & 0x20)

    @property
    def stop_requested(self) -> bool:
        return bool(self.flags & 0x40)


def _signed_byte(value: int) -> int:
    return value - 256 if value >= 128 else value


def _signed_word(low: int, high: int) -> int:
    value = low | (high << 8)
    return value - 65536 if value >= 32768 else value


def _car_dev(byte: int) -> int | None:
    return None if byte == 0x80 else _signed_byte(byte)


def parse_car_frame(data: bytes) -> CarTelemetry | None:
    if len(data) != CAR_FRAME_LEN:
        return None
    if data[0] != CAR_HEADER or data[1] != 0x01 or data[3] != CAR_FRAME_LEN:
        return None
    if data[CAR_FRAME_LEN - 1] != CAR_TAIL or data[40] != crc8(data[:40]):
        return None

    return CarTelemetry(
        seq=data[2],
        flags=data[4],
        mode=data[5],
        locked=data[6],
        dev=_car_dev(data[7]),
        width=data[8],
        dev_r=_car_dev(data[9]),
        wid_r=data[10],
        dev_g=_car_dev(data[11]),
        wid_g=data[12],
        dev_b=_car_dev(data[13]),
        wid_b=data[14],
        cmd_x=_signed_byte(data[15]),
        cmd_y=_signed_byte(data[16]),
        cmd_z=_signed_byte(data[17]),
        wheels=(
            _signed_word(data[18], data[19]),
            _signed_word(data[20], data[21]),
            _signed_word(data[22], data[23]),
            _signed_word(data[24], data[25]),
        ),
        vx=_signed_word(data[26], data[27]),
        vy=_signed_word(data[28], data[29]),
        heading=_signed_word(data[30], data[31]) / 10.0,
        target_angle=_signed_word(data[32], data[33]) / 10.0,
        gyro_z=_signed_word(data[34], data[35]) / 10.0,
        battery=_signed_word(data[36], data[37]) / 10.0,
        uptime_ms=data[38] | (data[39] << 8),
        raw=bytes(data),
    )
