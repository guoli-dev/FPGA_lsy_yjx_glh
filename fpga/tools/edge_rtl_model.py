"""edge_detect_96（2026-11-11 全分辨率版）的**周期精确**模型。

目的：本机没有 Verilog 仿真器（TD 只带 sim_release 库，不带 simulator），
所以把 RTL 的每一个寄存器/每一个时钟沿照抄成 Python，喂真实图像流进去，
再用 numpy 的参考 Sobel 比对输出。能抓到的 bug：窗口对齐、行奇偶交换、
行缓存读写时序、2 拍延迟、行列计数器回绕。

用法：
    python edge_rtl_model.py --image text --out %TEMP%\\edge_rtl.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from edge_compare import make_lines, make_shapes, make_text, to_gray


class EdgeRtl:
    """逐位复刻 edge_detect_96 的两级流水。"""

    def __init__(self, width: int, height: int, th: int = 80):
        self.W = width
        self.H = height
        self.GW = width // 4
        self.LAST = self.GW - 1
        self.th = th

        # 行缓存（模拟 ERAM），内容用 4 元组表示一组像素
        self.memA = [None] * self.GW
        self.memB = [None] * self.GW

        # 写侧
        self.x_grp = 0
        self.y_pos = 0
        self.par = 0

        # 一级流水
        self.a_q = None
        self.b_q = None
        self.bot_word_d = None
        self.bot_word_d2 = None
        self.x_d = 0
        self.y_d = 0
        self.u_d = 0
        self.l_d = 0
        self.v_d = 0
        self.par_d = 0
        self.addr_d1 = 0
        self.addr_d2 = 0
        self.par_d1 = 0
        self.par_d2 = 0
        self.v_d2 = 0

        # 上一组最后两个像素
        self.t_c2 = self.t_c1 = 0
        self.m_c2 = self.m_c1 = 0
        self.b_c2 = self.b_c1 = 0

        self.out = np.zeros((height, width), np.uint8)

    @staticmethod
    def _word(v):
        return (0, 0, 0, 0) if v is None else v

    def step(self, group, tvalid: bool, tuser: bool, tlast: bool) -> None:
        tuser_v = tuser and tvalid
        cur_addr = 0 if tuser_v else self.x_grp

        # ---------------- 组合计算（用当前寄存器值）----------------
        a_q = self.a_q
        b_q = self.b_q
        mid_word = self._word(b_q if self.par_d else a_q)
        top_word = self._word(a_q if self.par_d else b_q)

        bot = self._word(self.bot_word_d)

        # 6 列窗口：[-2, -1, 0, 1, 2, 3]
        t = [self.t_c2, self.t_c1, top_word[0], top_word[1], top_word[2], top_word[3]]
        m = [self.m_c2, self.m_c1, mid_word[0], mid_word[1], mid_word[2], mid_word[3]]
        b = [self.b_c2, self.b_c1, bot[0], bot[1], bot[2], bot[3]]

        V = [t[j] + 2 * m[j] + b[j] for j in range(6)]
        HT = [t[j] + 2 * t[j + 1] + t[j + 2] for j in range(4)]
        HB = [b[j] + 2 * b[j + 1] + b[j + 2] for j in range(4)]

        win_ok = (self.y_d >= 2) and (self.x_d != 0)
        px = []
        for i in range(4):
            gx = V[i] - V[i + 2]
            gy = HT[i] - HB[i]
            mag = abs(gx) + abs(gy)
            px.append(255 if (win_ok and mag >= self.th) else 0)

        if self.v_d and self.y_d < self.H and self.x_d < self.GW:
            base = self.x_d * 4
            self.out[self.y_d, base:base + 4] = px

        # ---------------- 寄存器更新（非阻塞，全部用旧值）----------------
        v_old = self.v_d
        a_next = self.memA[cur_addr]
        b_next = self.memB[cur_addr]

        # 写端口：晚两拍
        if self.v_d2:
            if self.par_d2:
                self.memA[self.addr_d2] = self.bot_word_d2
            else:
                self.memB[self.addr_d2] = self.bot_word_d2

        # 位移必须从后往前赋值：RTL 里是非阻塞赋值，二级寄存器用的是**旧**的一级值
        self.bot_word_d2 = self.bot_word_d
        self.bot_word_d = group
        self.addr_d2 = self.addr_d1
        self.addr_d1 = cur_addr
        self.par_d2 = self.par_d1
        self.par_d1 = self.par
        self.v_d2 = self.v_d
        self.v_d = 1 if tvalid else 0

        self.a_q = a_next
        self.b_q = b_next
        self.x_d = cur_addr
        self.y_d = self.y_pos
        self.u_d = 1 if tuser else 0
        self.l_d = 1 if tlast else 0
        self.par_d = self.par

        # 上一组最后两个像素：RTL 里是 `else if (v_d)` 更新，用的是当前拍的值
        if v_old:
            self.t_c2, self.t_c1 = top_word[2], top_word[3]
            self.m_c2, self.m_c1 = mid_word[2], mid_word[3]
            self.b_c2, self.b_c1 = bot[2], bot[3]


        # 计数器
        if tvalid:
            if tuser:
                self.x_grp = 1
                self.y_pos = 0
                self.par = 0
            elif cur_addr == self.LAST:
                self.x_grp = 0
                self.par ^= 1
                self.y_pos = 0 if self.y_pos == self.H - 1 else self.y_pos + 1
            else:
                self.x_grp += 1


def run(rgb: np.ndarray, th: int = 80) -> np.ndarray:
    h, w = rgb.shape[:2]
    assert w % 4 == 0
    gray = to_gray(rgb)
    model = EdgeRtl(w, h, th)

    # 逐拍喂入：tuser 只在**帧首**那一拍拉高，tlast 在每行最后一拍
    for y in range(h):
        for g in range(w // 4):
            px = gray[y, g * 4:(g + 1) * 4]
            model.step(tuple(int(v) for v in px), True, (y == 0 and g == 0), g == (w // 4 - 1))
    return model.out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", default="text", choices=["text", "shapes", "lines"])
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    rgb = {"text": make_text, "shapes": make_shapes, "lines": make_lines}[args.image]()
    got = run(rgb)

    from edge_compare import sobel_full

    ref_mag = sobel_full(to_gray(rgb))
    ref_mag[:2, :] = 0
    ref_mag[:, :1] = 0
    ref = np.where(ref_mag >= 80, 255, 0).astype(np.uint8)

    # RTL 用后向窗口：3x3 窗口中心在第 i-1 个像素 / 第 y-1 行，
    # 所以边缘图相对原图整体**右移 1 px、下移 1 行**（旧版是右移 2 px）。
    ref_shift = np.zeros_like(ref)
    ref_shift[1:, 1:] = ref[:-1, :-1]
    # 模型内部已经用 x_d 对齐，这里直接比
    diff = (got != ref_shift)
    print(f"image={args.image} {got.shape}")
    print(f"RTL 边缘像素 {int((got > 0).sum())} / 参考 {int((ref_shift > 0).sum())}")
    print(f"不一致像素 {int(diff.sum())} ({100.0 * diff.mean():.2f}%)")

    band = (got > 0) | (ref_shift > 0)
    if band.any():
        print(f"在任意一边为边缘的位置上，不一致率 {100.0 * diff[band].mean():.2f}%")

    if args.out:
        from PIL import Image

        canvas = np.zeros((got.shape[0], got.shape[1] * 3 + 12, 3), np.uint8)
        canvas[:, :got.shape[1]] = np.dstack([got] * 3)
        canvas[:, got.shape[1] + 6:got.shape[1] * 2 + 6] = np.dstack([ref_shift] * 3)
        canvas[:, got.shape[1] * 2 + 12:] = np.dstack([rgb] * 3)[..., :3]
        Image.fromarray(canvas).save(args.out)
        print(f"对比图 -> {args.out}")


if __name__ == "__main__":
    main()
