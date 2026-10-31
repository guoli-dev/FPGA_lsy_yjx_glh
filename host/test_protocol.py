import unittest

from protocol import (
    ColorPacket,
    MotionPacket,
    StatusPacket,
    encode_color_request,
    encode_mode,
    encode_motion_request,
    encode_status_request,
    parse_packet,
)


class ProtocolTests(unittest.TestCase):
    def test_status_packet(self):
        packet = parse_packet(bytes.fromhex("AA 03 3C 00 01 55"))
        self.assertIsInstance(packet, StatusPacket)
        self.assertEqual(packet.mode, 3)
        self.assertEqual(packet.fps, 60)
        self.assertTrue(packet.link)
        self.assertIsNone(packet.frame_count)

    def test_extended_status_packet(self):
        packet = parse_packet(bytes.fromhex("AA 03 3C 00 01 25 00 02 00 41 01 55"))
        self.assertIsInstance(packet, StatusPacket)
        self.assertEqual(packet.frame_count, 37)
        self.assertEqual(packet.latency_frames, 2)
        self.assertEqual(packet.motion_count, 321)

    def test_ethernet_color_packet(self):
        packet = parse_packet(bytes((0xAB, 0xF6, 20, 50, 0x80, 0, 0, 10, 8, 75, 0x55)))
        self.assertIsInstance(packet, ColorPacket)
        red, green, blue = packet.blocks
        self.assertEqual((red.center_x, red.center_y, red.width), (560, 200, 160))
        self.assertFalse(green.detected)
        self.assertEqual((blue.center_x, blue.center_y, blue.width), (720, 300, 64))

    def test_compact_color_packet(self):
        packet = parse_packet(bytes((0xAA, 0xF6, 20, 0x80, 0, 10, 8)))
        self.assertIsInstance(packet, ColorPacket)
        red, green, blue = packet.blocks
        self.assertEqual((red.deviation, red.center_x, red.width), (-10, 560, 160))
        self.assertIsNone(red.center_y)
        self.assertFalse(green.detected)
        self.assertEqual((blue.deviation, blue.center_x, blue.width), (10, 720, 64))

    def test_commands_and_invalid_frames(self):
        self.assertEqual(encode_mode(4), b"\x01\x04")
        self.assertEqual(encode_status_request(), b"\x02")
        self.assertEqual(encode_color_request(), b"\x03")
        self.assertEqual(encode_motion_request(), b"\x04")
        with self.assertRaises(ValueError):
            encode_mode(5)
        self.assertIsNone(parse_packet(b"bad"))
        self.assertIsNone(parse_packet(bytes.fromhex("AA 07 00 00 01 55")))

    def test_motion_box_packet(self):
        # box = {10'd0, 11'd0, valid=1, left=100, right=300, top=50, bottom=200}
        box = (1 << 42) | (100 << 31) | (300 << 20) | (50 << 10) | 200
        data = bytes((0xAC,)) + box.to_bytes(8, "little") + bytes((0x2A, 0x01, 0x55))
        packet = parse_packet(data)
        self.assertIsInstance(packet, MotionPacket)
        self.assertTrue(packet.box.detected)
        self.assertEqual(
            (packet.box.left, packet.box.right, packet.box.top, packet.box.bottom),
            (100, 300, 50, 200),
        )
        self.assertEqual(packet.box.motion_count, 298)

    def test_motion_box_no_detect(self):
        data = bytes((0xAC,)) + bytes(8) + bytes((0x00, 0x00, 0x55))
        packet = parse_packet(data)
        self.assertIsInstance(packet, MotionPacket)
        self.assertFalse(packet.box.detected)
        self.assertIsNone(packet.box.left)
        self.assertEqual(packet.box.motion_count, 0)


if __name__ == "__main__":
    unittest.main()
