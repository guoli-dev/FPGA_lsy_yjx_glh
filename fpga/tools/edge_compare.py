"""边缘检测算法对比工具（位精确模型，不依赖任何仿真器）

用途
----
`isp_top.v` 里的 `edge_detect_96` 没有 testbench，也没有可用的 Verilog 仿真器。
本脚本用 numpy 逐位复刻 RTL 的行为，再实现若干候选改法，用同一批测试图对比：

    python edge_compare.py --out %TEMP%\\edge_out

输出的 PNG 可以直接看，`--metrics` 会打印量化指标（峰值响应、边缘宽度、覆盖率）。

RTL 事实（对应 isp_top.v 行号）
-------------------------------
- 灰度：`R>>2 + G>>1 + B>>2`，范围 0..253（L2046-2051）
- 水平 2:1 降采样：相邻两像素求平均成 640 个 pair（L2058-2061）
- Sobel 在 pair 网格上做，窗口水平基线 = 4 像素
- 输出纯二值：`mag >= th ? 0xffffff : 0x000000`（L2112-2116）
- 窗口中心偏左：mag0 的中心是 pair 2g-1，输出到像素 4g..4g+1 —— 整体 +2 px 右移
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

TH_DEFAULT = 80


# ---------------------------------------------------------------- 基础算子

def to_gray(rgb: np.ndarray) -> np.ndarray:
    """复刻 RTL 的亮度近似：R>>2 + G>>1 + B>>2（最大值 253，不会溢出 8 bit）。"""
    rgb = rgb.astype(np.int32)
    return (rgb[..., 0] >> 2) + (rgb[..., 1] >> 1) + (rgb[..., 2] >> 2)


def _sobel_abs(a00, a01, a02, a10, a11, a12, a20, a21, a22):
    """|Gx| + |Gy|，与 RTL 的 sobel_mag 完全一致。"""
    gx = a02 + 2 * a12 + a22 - a00 - 2 * a10 - a20
    gy = a00 + 2 * a01 + a02 - a20 - 2 * a21 - a22
    return np.abs(gx) + np.abs(gy)


def sobel_full(gray: np.ndarray) -> np.ndarray:
    """全分辨率 3x3 Sobel，边界用 0 填充，输出与输入同尺寸、窗口居中。"""
    g = gray.astype(np.int32)
    p = np.pad(g, 1, mode="constant")
    return _sobel_abs(
        p[0:-2, 0:-2], p[0:-2, 1:-1], p[0:-2, 2:],
        p[1:-1, 0:-2], p[1:-1, 1:-1], p[1:-1, 2:],
        p[2:, 0:-2], p[2:, 1:-1], p[2:, 2:],
    )


def sobel_pairs(gray: np.ndarray) -> np.ndarray:
    """复刻 RTL：先水平两像素求平均成 pair，再在 pair 网格上做 3x3。

    返回 pair 网格的梯度幅值，形状 (H, W/2)。
    """
    g = gray.astype(np.int32)
    pairs = (g[:, 0::2] + g[:, 1::2]) >> 1          # (H, W/2)
    p = np.pad(pairs, 1, mode="constant")
    return _sobel_abs(
        p[0:-2, 0:-2], p[0:-2, 1:-1], p[0:-2, 2:],
        p[1:-1, 0:-2], p[1:-1, 1:-1], p[1:-1, 2:],
        p[2:, 0:-2], p[2:, 1:-1], p[2:, 2:],
    )


# ---------------------------------------------------------------- 三种实现

def method_current(rgb: np.ndarray, th: int = TH_DEFAULT) -> np.ndarray:
    """现状：pair 平均 + pair 网格 Sobel + 二值。返回 0/255 灰度图。"""
    mag = sobel_pairs(to_gray(rgb))                 # (H, 320)
    up = np.repeat(mag, 2, axis=1)                  # 每个 pair 覆盖 2 像素
    up = np.repeat(up, 1, axis=0)
    # 整体 +2 px：mag[g] 代表像素 4g-2 的中心
    shifted = np.zeros_like(up)
    shifted[:, 2:] = up[:, :-2]
    out = np.where(shifted >= th, 255, 0).astype(np.uint8)
    out[:2, :] = 0
    return out


def method_pairmax(rgb: np.ndarray, th: int = TH_DEFAULT, grad: bool = True) -> np.ndarray:
    """方案 1：pair 取最大值代替平均 + 梯度强度输出（不改变流水结构）。"""
    gray = to_gray(rgb).astype(np.int32)
    pairs = np.maximum(gray[:, 0::2], gray[:, 1::2])
    p = np.pad(pairs, 1, mode="constant")
    mag = _sobel_abs(
        p[0:-2, 0:-2], p[0:-2, 1:-1], p[0:-2, 2:],
        p[1:-1, 0:-2], p[1:-1, 1:-1], p[1:-1, 2:],
        p[2:, 0:-2], p[2:, 1:-1], p[2:, 2:],
    )
    up = np.repeat(mag, 2, axis=1)
    shifted = np.zeros_like(up)
    shifted[:, 2:] = up[:, :-2]
    if not grad:
        out = np.where(shifted >= th, 255, 0).astype(np.uint8)
    else:
        out = gray_level(shifted, th)
    out[:2, :] = 0
    return out


def method_fullres(rgb: np.ndarray, th: int = TH_DEFAULT, nms: bool = True,
                   grad: bool = True, weak_ratio: float = 0.5) -> np.ndarray:
    """方案 2：全分辨率 3x3 + 左邻非极大值抑制 + 强弱双阶输出。"""
    mag = sobel_full(to_gray(rgb))                  # (H, W)
    if nms:
        left = np.zeros_like(mag)
        left[:, 1:] = mag[:, :-1]
        keep = mag >= left
        mag = np.where(keep, mag, 0)
    mag = np.pad(mag, ((0, 0), (1, 0)))[:, :-1]     # 取消 NMS 带来的 1 px 左移
    mag[:2, :] = 0
    if not grad:
        return np.where(mag >= th, 255, 0).astype(np.uint8)
    return gray_level(mag, th, weak_ratio)


def gray_level(mag: np.ndarray, th: int, weak_ratio: float = 0.5) -> np.ndarray:
    """梯度幅值 -> 8 位灰度。

    强边（mag >= th）饱和到 255，弱边按 2*mag 线性映射到 0..255，
    这样既能保住"边缘=纯白"的既有语义（卡通描边依赖它），又能让弱边看出层次。
    """
    weak = np.clip(mag * 2, 0, 255)
    out = np.where(mag >= th, 255, weak).astype(np.uint8)
    out[mag < th * weak_ratio] = 0
    return out


def three_level(mag: np.ndarray, th: int) -> np.ndarray:
    """强边纯白、弱边中灰、其余全黑 —— 三级量化，纯比较器实现。"""
    out = np.zeros_like(mag, dtype=np.uint8)
    out[mag >= th] = 255
    out[(mag >= th // 2) & (mag < th)] = 128
    return out


def method_fullres_dilate(rgb: np.ndarray, th: int = TH_DEFAULT) -> np.ndarray:
    """全分辨率 + NMS + 向右膨胀 1 px（只用 1 个寄存器，把 1 px 线变 2 px）。"""
    mag = sobel_full(to_gray(rgb))
    left = np.zeros_like(mag)
    left[:, 1:] = mag[:, :-1]
    mag = np.where(mag >= left, mag, 0)
    mag = np.pad(mag, ((0, 0), (1, 0)))[:, :-1]
    keep = mag >= th
    dil = keep.copy()
    dil[:, :-1] |= keep[:, 1:]
    out = np.where(dil, 255, 0).astype(np.uint8)
    out[:2, :] = 0
    return out


# ---------------------------------------------------------------- 指标

def measure(image: np.ndarray, name: str, region=None) -> dict:
    band = image > 0
    if region is not None:
        band = band[region]
        image = image[region]
    rows = max(1, band.shape[0])
    return {
        "name": name,
        "peak": int(image.max()),
        "px_per_row": round(float(band.sum()) / rows, 2),
        "mean_brightness": round(float(image[band].mean()) if band.any() else 0.0, 1),
        "total": int(band.sum()),
    }


def run_metrics(rgb: np.ndarray, label: str, region=None) -> None:
    print(f"\n== {label}")
    variants = (
        ("现状  pair-average + 二值", method_current),
        ("方案1 pair-max  + 二值", lambda im, **k: method_pairmax(im, grad=False)),
        ("方案1 pair-max  + 三级", lambda im, **k: three_level(sobel_from_pairmax(im), 80)),
        ("方案2 全分辨率 + 二值", lambda im, **k: method_fullres(im, nms=False, grad=False)),
        ("方案2 全分辨率 + NMS + 二值", lambda im, **k: method_fullres(im, nms=True, grad=False)),
        ("方案2 全分辨率 + NMS + 三级", lambda im, **k: three_level(sobel_nms(im), 80)),
        ("方案2 全分辨率 + NMS + 膨胀", method_fullres_dilate),
    )
    for name, fn in variants:
        m = measure(fn(rgb), name, region)
        print("  {:<32} 亮边/行 {:6.2f} | 平均亮度 {:5.1f} | 总数 {:6d}".format(
            m["name"], m["px_per_row"], m["mean_brightness"], m["total"]))


def sobel_from_pairmax(rgb: np.ndarray) -> np.ndarray:
    gray = to_gray(rgb).astype(np.int32)
    pairs = np.maximum(gray[:, 0::2], gray[:, 1::2])
    p = np.pad(pairs, 1, mode="constant")
    mag = _sobel_abs(
        p[0:-2, 0:-2], p[0:-2, 1:-1], p[0:-2, 2:],
        p[1:-1, 0:-2], p[1:-1, 1:-1], p[1:-1, 2:],
        p[2:, 0:-2], p[2:, 1:-1], p[2:, 2:],
    )
    return np.repeat(mag, 2, axis=1)


def sobel_nms(rgb: np.ndarray) -> np.ndarray:
    mag = sobel_full(to_gray(rgb))
    left = np.zeros_like(mag)
    left[:, 1:] = mag[:, :-1]
    mag = np.where(mag >= left, mag, 0)
    mag = np.pad(mag, ((0, 0), (1, 0)))[:, :-1]
    mag[:2, :] = 0
    return mag


# ---------------------------------------------------------------- 测试图

def make_lines(h=180, w=640) -> np.ndarray:
    """若干条 1px / 2px / 4px 竖线和斜线，检验分辨率与定位。"""
    img = np.zeros((h, w), np.uint8)
    img[:, 60] = 255
    img[:, 140] = 60
    img[:, 220:222] = 255
    img[40:140, 300] = 255
    img[60:160, 380] = 180
    for i in range(0, 120):
        y = 20 + i
        x = 440 + i // 4
        if x < w:
            img[y, x] = 255
    return np.dstack([img, img, img])


def make_shapes(h=240, w=640) -> np.ndarray:
    """几何形状 + 彩色块，模拟演示场景。"""
    img = np.zeros((h, w, 3), np.uint8)
    img[:, :, 0] = 30
    img[:, :, 1] = 34
    img[:, :, 2] = 40
    img[40:200, 40:180] = (220, 40, 40)
    img[60:180, 220:360] = (40, 210, 60)
    img[80:160, 400:520] = (50, 70, 230)
    yy, xx = np.ogrid[:h, :w]
    disk = (yy - 120) ** 2 + (xx - 570) ** 2 < 45 ** 2
    img[disk] = (230, 220, 60)
    return img


def make_text(h=240, w=640) -> np.ndarray:
    """文字是最强的高频细节，直接检验"糊不糊"。"""
    from PIL import Image, ImageDraw, ImageFont

    canvas = Image.new("RGB", (w, h), (16, 18, 22))
    draw = ImageDraw.Draw(canvas)
    font = None
    for candidate in (
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\simhei.ttf",
        r"C:\Windows\Fonts\arial.ttf",
    ):
        if Path(candidate).exists():
            try:
                font = ImageFont.truetype(candidate, 34)
                break
            except OSError:
                continue
    if font is None:
        font = ImageFont.load_default()
    draw.text((24, 20), "边缘检测 EDGE", fill=(240, 240, 240), font=font)
    draw.text((24, 80), "PH1P35 实时视觉", fill=(235, 235, 235), font=font)
    draw.text((24, 150), "0123456789 ABCdef", fill=(220, 220, 220), font=font)
    return np.asarray(canvas, np.uint8)


def make_noise(h=240, w=640, seed=7) -> np.ndarray:
    """低对比度噪声场景：检验改动会不会把噪声放大成雪花。"""
    rng = np.random.default_rng(seed)
    base = np.full((h, w, 3), 110, np.int16)
    base += rng.integers(-6, 7, size=(h, w, 3), dtype=np.int16)
    base[80:160, 200:440] += 25
    return np.clip(base, 0, 255).astype(np.uint8)


def save_comparison(rgb: np.ndarray, path: Path) -> None:
    from PIL import Image

    panels = [
        ("source", rgb),
        ("current", np.dstack([method_current(rgb)] * 3)),
        ("full", np.dstack([method_fullres(rgb, nms=False, grad=False)] * 3)),
        ("full+nms", np.dstack([method_fullres(rgb, nms=True, grad=False)] * 3)),
        ("full+nms+dilate", np.dstack([method_fullres_dilate(rgb)] * 3)),
    ]
    tiles = []
    for title, arr in panels:
        tile = np.ascontiguousarray(arr.astype(np.uint8))
        tiles.append(tile)
    h = max(t.shape[0] for t in tiles)
    gap = 6
    total_w = sum(t.shape[1] for t in tiles) + gap * (len(tiles) - 1)
    canvas = np.zeros((h, total_w, 3), np.uint8)
    x = 0
    for t in tiles:
        canvas[: t.shape[0], x : x + t.shape[1]] = t
        x += t.shape[1] + gap
    Image.fromarray(canvas).save(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=None, help="输出 PNG 的目录")
    parser.add_argument("--metrics", action="store_true", help="打印量化指标")
    args = parser.parse_args()

    cases = {
        "lines": make_lines(),
        "shapes": make_shapes(),
        "text": make_text(),
        "noise": make_noise(),
    }

    if args.metrics:
        for label, rgb in cases.items():
            run_metrics(rgb, label)

    if args.out:
        out = Path(args.out)
        out.mkdir(parents=True, exist_ok=True)
        for label, rgb in cases.items():
            save_comparison(rgb, out / f"{label}.png")
        print(f"\n对比图已写入 {out}")


if __name__ == "__main__":
    main()
