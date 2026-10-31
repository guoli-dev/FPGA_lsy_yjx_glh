import queue
import unittest

from car_link import CarLink
from protocol import CAR_FRAME_LEN, crc8, parse_car_frame


def _word(value):
    value &= 0xFFFF
    return (value & 0xFF, (value >> 8) & 0xFF)


def build_frame(seq=1):
    frame = bytearray(CAR_FRAME_LEN)
    frame[0] = 0xC5
    frame[1] = 0x01
    frame[2] = seq
    frame[3] = CAR_FRAME_LEN
    frame[4] = 0x3F                      # IMU/零漂/追踪/到达/见目标/锁定
    frame[5] = 1                         # 目标选红色
    frame[6] = 2                         # 锁定绿色
    frame[7] = (-10) & 0xFF
    frame[8] = 40
    frame[9], frame[10] = (-10) & 0xFF, 40
    frame[11], frame[12] = 0x80, 0       # 绿色无效
    frame[13], frame[14] = 12, 55
    frame[15], frame[16], frame[17] = (-3) & 0xFF, 20, (-5) & 0xFF
    frame[18:20] = _word(-123)
    frame[20:22] = _word(456)
    frame[22:24] = _word(-7)
    frame[24:26] = _word(1000)
    frame[26:28] = _word(-42)
    frame[28:30] = _word(86)
    frame[30:32] = _word(-1234)
    frame[32:34] = _word(567)
    frame[34:36] = _word(-25)
    frame[36:38] = _word(121)
    frame[38:40] = _word(4321)
    frame[40] = crc8(bytes(frame[:40]))
    frame[41] = 0x5C
    return bytes(frame)


class CarProtocolTests(unittest.TestCase):
    def test_parse_car_frame(self):
        packet = parse_car_frame(build_frame())
        self.assertIsNotNone(packet)
        self.assertEqual(packet.seq, 1)
        self.assertEqual((packet.mode, packet.locked), (1, 2))
        self.assertEqual(packet.dev, -10)
        self.assertEqual(packet.width, 40)
        self.assertIsNone(packet.dev_g)
        self.assertEqual(packet.wheels, (-123, 456, -7, 1000))
        self.assertEqual((packet.vx, packet.vy), (-42, 86))
        self.assertAlmostEqual(packet.heading, -123.4)
        self.assertAlmostEqual(packet.target_angle, 56.7)
        self.assertAlmostEqual(packet.gyro_z, -2.5)
        self.assertAlmostEqual(packet.battery, 12.1)
        self.assertEqual(packet.uptime_ms, 4321)
        self.assertTrue(packet.imu_ready and packet.zero_done and packet.tracking)
        self.assertTrue(packet.arrived and packet.target_seen and packet.locked_active)
        self.assertFalse(packet.stop_requested)

    def test_reject_bad_frames(self):
        good = build_frame()
        bad_crc = bytearray(good)
        bad_crc[20] ^= 0x01
        self.assertIsNone(parse_car_frame(bytes(bad_crc)))
        self.assertIsNone(parse_car_frame(good[:-1]))
        bad_type = good[:1] + b"\x02" + good[2:]
        self.assertIsNone(parse_car_frame(bad_type))

    def test_serial_resync(self):
        events = queue.Queue()
        link = CarLink(events, "TEST")
        frames = build_frame(1) + build_frame(2) + build_frame(3)[:9]
        buffer = bytearray(b"\x00\xAA\xC5" + frames)
        link._drain(buffer)
        seqs = []
        while not events.empty():
            kind, packet, _ = events.get()
            if kind == "car":
                seqs.append(packet.seq)
        self.assertEqual(seqs, [1, 2])
        self.assertEqual(len(buffer), 9)


if __name__ == "__main__":
    unittest.main()
