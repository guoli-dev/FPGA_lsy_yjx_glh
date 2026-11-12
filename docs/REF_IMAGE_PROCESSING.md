# 参考实现图像处理代码精读（cz666GOUTOU / fpga-vision-servo-ab-public）

> 对象：`A_board/lab_ex3_osd/user_source/hdl_source/` 下的 `vision.v`（1814 行，14 个模块）与 ISP 侧图像处理模块。
> 本文只记录**能搬到本仓库**的技术点。所有资源数字都是按代码结构**估算**，未综合。

## 0. 两张不同的接口风格

| 风格 | 信号 | 数据宽度 | 反压 |
|---|---|---|---|
| `vision.v` 系 | `clk / rst_n / vs / hs / de` + 24bit RGB | 1 像素/拍 | 无，固定延迟 |
| `isp/` 系 | AXI4-Stream `tdata/tvalid/tuser/tlast` | 4 像素/拍（RAW10=40bit、RGB888=96bit） | `tready` |

本仓库是后者。**注意**：参考实现的 `awb.v` 里 `O_tuser` 是**组合直通**、`O_tvalid` 延两拍、`O_tlast` 用 valid 下降沿伪造——这正是本仓库 `color_box` 帧复位 bug 的成因，看这类代码要条件反射。

## 1. `vision.v` 顶层结构

`pre_rgb` → `rgb2ycbcr_888` 取 Y → **10 个效果器全部并行常驻** → 纯组合 mux 按 `proc_sel` 选一路。

- 模式表：0 bypass / 1 gray / 2 binary / 3 histogram / 4 sobel / 5 gauss / 7 invert / 9 gamma / 10 false_color / 11 cartoon / 12 auto
- **各支路端到端延迟不等**（以 `pre_rgb` 为 0 拍，`rgb2ycbcr` 的 2 拍是所有 Y 分支的公共前缀）：

  | 支路 | 端到端 | 构成 |
  |---|---|---|
  | bypass | 1 | 直接来自 `pre_rgb` |
  | gray / binary / invert / gamma / false_color | 3 | Y 的 2 拍 + 各自 1 拍 |
  | sobel / gaussian | 4 | Y 的 2 拍 + 窗口/就绪 2 拍 |
  | histogram | 5 | Y 的 2 拍 + 三级像素流水 |
  | cartoon | 6 | 从 `pre_rgb` 直接进，6 级移位寄存器 |

  切模式时画面相位会跳 1~5 拍；后面挂 OSD 叠加层必须按 DE 重新对齐，或把各路统一补到 6 拍。

## 2. 逐模块要点

| 模块 | 算法 | 定点/实现技巧 | 延迟 | 资源（估） |
|---|---|---|---|---|
| `video_proc_gray_binary` | `Y >= THRESHOLD ? 255 : 0` | 阈值做成 `parameter` | 1 | ~20 LUT |
| `rgb2ycbcr_888` | `Y = (77R+150G+29B+128)>>8` | **Cb/Cr 恒 128，根本没算**，就是个 Y 提取器 | 2 | 3 个乘法（0~3 DSP） |
| `video_proc_histogram` | 帧级 **min-max 拉伸**（非均衡） | **256 项 Q8 倒数表**代替除法，像素路径只剩 1 个 8×16 乘法 | 3 | 1 RAM + 1 DSP |
| `video_proc_sobel_rows` | 全分辨率 3×3，**输出灰度梯度** `min(255,abs(gx)+abs(gy))` | L1 范数；`abs` 用 `sign ? ~x+1 : x` | 2 | 2 RAM（共享时 0）+ ~50 LUT |
| `video_proc_gaussian_rows` | 3×3 高斯 `[1 2 1;2 4 2;1 2 1]>>4` | **一次 9 抽头加权和**（非两遍 1D），系数全是 1/2/4 纯移位 | 2 | 2 RAM（共享时 0） |
| `video_proc_gamma` | **16 段分段常数**，不是插值 | 纯 `case(Y[7:4])`，0 乘法 0 RAM | 1 | ~20 LUT |
| `video_proc_false_color` | 256 项伪彩表 | ROM 查表 | 1 | 1 RAM |
| `video_proc_cartoon` | 每通道取高 2 bit（64 色） | **没有边缘/描边**，纯量化 | 6 | ~20 LUT |
| `video_filter_row_store` | 两级行延迟 | 预取 + 写前递（见 §3） | — | 2 RAM |

## 3. 最值钱的一块：行缓存「预取 + 写前递」

`video_filter_row_store`（L1791-1814）和 `sobel_rows`/`gaussian_rows` 的私有分支（L1005-1037）：

```verilog
prefetch_addr = (!rst_n || !de || col == W-1) ? 0 : col + 1;   // 读"下一拍要用的列"
read0 <= line0[prefetch_addr];                                 // 同步读 → 能推断成 ERAM
collision <= rst_n && de && (prefetch_addr == col);            // 同拍读写冲突
forward0 <= gray;                                              // 写前递数据
if (de) line0[col] <= gray;                                    // 写当前列
row1 = collision ? forward0 : read0;                           // 冲突时用前递值
```

**为什么必须这样**：块 RAM 只能同步读，地址打一拍才出数；把地址提前一列，数据正好在下一拍和像素对齐 → **零额外延迟**。若按"当拍读、当拍用"写，综合器只能推断成分布式 RAM。

本仓库实测反例：`edge_detect_96` 初版 `ram_style="block"` 被 TD 忽略（正确值是 `"bram"`），两块 320×32 摊成 512 个 DRAM LUT。

**三个边角条件**（漏一个就出横纹）：末列地址回 0、DE 空泡时地址归 0、宽度=1 时预取撞自己。

**契约**：每个 DE burst ≤ 行宽拍、行间至少 1 个空白拍，否则列计数器复位不了。

**共享机制 `EXTERNAL_ROWS`**：编译期开关，为 1 时消费者不例化自己的行 RAM，直接接共享的 `row1/row2`。Sobel 和 Gaussian 因此共用同一组 2 块 RAM（4 块降到 2 块），各自的 9 个窗口寄存器和就绪条件仍独立。

## 4. 直方图拉伸的倒数查表法

- `gain_table[n] = round(255×256/n)`，n=1..255 → Q8 的 `255/range`，最大 65280
- 拉伸系数整帧恒定，所以只在**场消隐**算一次；像素路径只有三级：
  `diff = max(Y-min,0)` → `product = diff*gain_q8` → `(product+128)>>8` 饱和
- 表用 256×16 RAM，1 块 ERAM

**对本仓库的判断**：思路要抄（一次性系数 + 场消隐提交），但**256 项表不要抄**——我们 ERAM 紧张，而且只有一次除法。可以用 `awb.v` 的串行除法器，或 `th ≈ (Σmag>>20)*k` 纯移位。

## 5. 其他值得记的技巧

### 5.1 串行除法器（`awb.v` L515-586）
13 次迭代、1 个 30bit 减法器、固定除数、Q8 结果，与原来的 50 拍接口用延迟计数器对齐。
**替换 `div_gen`：~3635 slice → ~200 slice，省约 3400 slice（19%）**。这是全仓库对本仓库最值钱的一条，但要重验 AWB 时序（它正是 ISP 域最差路径的源头）。

### 5.2 AWB 延迟线可以去掉
`signal_delay.v` 用 5 个 bank（512×20 ×4 + 512×16）替代 2048×96 的生成 IP，10 ERAM → 5 ERAM。
而 `awb.v` 的新结构是"帧末算、下一帧 tuser 提交"，**50 拍延迟线已经不需要**，整条去掉可省 10 ERAM + ~250 slice。

### 5.3 LSC 的双线性递推（`raw10_lsc.v`）
把二维插值变成「每拍一次加法」：
- 垂直方向：每个 (平面, 列节点) 存 `row_knot` 和 `row_dy`，每个行尾 `row_knot += row_dy`
- 水平方向：每个 cell 起点装 `h_acc = left_knot<<8`、`h_step = right_knot-left_knot`，之后每拍 `h_acc += h_step<<2`
- 一拍 4 像素用 `dx*0/1/2/3`，四舍五入后取 Q2.10
- 只剩 4 个 `raw10 × 12bit gain` 真乘法（4 DSP）

**注意 L33-35 的坑**：用运行时整数索引去访问打包参数，TD 会推断出宽地址乘法 → 面积爆炸。对策是把每个 band 的差值预计算成常量，再用 one-hot 选择。

**对本仓库**：DSP 只剩 1 个，整块搬不动（要 4 DSP）；但"一次性系数 + 递推"的思想可用。

### 5.4 ROM 换乘法器
- `raw10_dgain`：`y = f(x_low) + x_high×64`，把 10×12 乘法拆成「8bit 查表 + 2bit 加法」，*0 DSP*，代价 2 块 ERAM
- `rgb_contrast`：6 块 1024×8 ROM 换 12 个乘法器
- `rgb_saturation`：手动例化 DSP 原语，让**一个 DSP 同时做预减→乘法→后加**，12 通道 12 DSP、0 LUT 乘法

### 5.5 窄位宽 ALU 分次做宽运算（`camera_auto_exposure`）
39bit 的 `sample_sum × coeff` 用 **1 个 13bit 加法器分 3 次**算完，每次只处理一个 limb。适合帧级宽位宽运算（32bit 帧和、自动阈值）。

### 5.6 gamma 根本不需要乘法器
`video_proc_gamma` 是 16 段 `case`，0 DSP 0 RAM。
对照本仓库 `gamma_96` 的 `(v-128)*3>>2` **吃掉了 24 个 DSP**（总共 39 个）——改成 16 段 case 或移位加法可释放 24 个 DSP，代价约 100 LUT。

### 5.7 帧参数邮箱
`raw10_ae_stats` / `raw10_auto_gain` 的写法：toggle 同步 2 级 + payload + `epoch` + ack，**只在 `tuser` 提交**，保证整帧参数恒定。
适合把色块阈值、边缘门限做成 UART 可调。

## 6. 坑清单

| # | 坑 | 后果 |
|---|---|---|
| 1 | 目录里有**两份 `module awb`**（`awb.v` 新 / `isp/awb/awb.v` 旧 8 除法器） | 编错就面积翻倍 |
| 2 | `awb.v` 的 `O_tuser` 组合直通 + `O_tvalid` 延 2 拍 + `O_tlast` 伪造 | 下游"tuser 与 tvalid 同拍"的假设全错 |
| 3 | **Q12 vs Q16 增益混用**（`auto_white_balance` 是 `[19:12]`，`awb.v` 是 `[23:16]`） | 直接过曝/发黑 |
| 4 | `auto_white_balance` 的 frame_start/end 比数据早 1 拍 | 帧边界错位 |
| 5 | `BLC` 的 `O_tdest` 声明了从未赋值 | 悬空 |
| 6 | `image_correction` 丢掉真实 tlast/tuser，且依赖行间空泡 >10 拍 | 空泡不足会并行 |
| 7 | sobel 与 gaussian 的末列处理**不一样**（sobel 在 W-1 清零，gaussian 用 `line_end_pending` 停住等 DE） | 互相照抄会少/多一列 |
| 8 | `histogram` 的 `range==0` → 增益 0 → 全黑 | 纯色画面黑屏 |
| 9 | `raw10_lsc` 运行时整数索引访问参数表 → TD 推断宽地址乘法 | 面积爆炸 |
| 10 | `SHARE_FILTER_ROWS` 用 `==` 精确匹配 720p | 换分辨率静默失去共享 |
| 11 | 注释与代码不符（cartoon 说 edge 实际纯量化；gamma 说 64 点插值实际 16 段；sobel 说 border replication 实际黑边） | **只信代码** |

## 7. 对本仓库的搬运优先级

| 序 | 搬什么 | 收益 | 风险 |
|---|---|---|---|
| 1 | 串行除法器替换 AWB 的 `div_gen` | **−3400 slice** | 中（AWB 是 ISP 最差路径源头） |
| 2 | AWB 延迟线去掉 | −10 ERAM、−250 slice | 中（帧对齐要重验） |
| 3 | 行缓存预取 + 写前递（已落地） | −512 DRAM LUT | 低 |
| 4 | gamma 换 16 段 case / 移位 | **释放 24 个 DSP**，+100 LUT | 低-中 |
| 5 | 曲线/增益用 ROM 或 case 代替乘法 | 省 DSP | 低 |
| 6 | 窄位宽 ALU | 省 20~30 slice | 低 |
| 7 | 帧参数邮箱 | 阈值可现场调 | 低 |

**结论**：参考实现验证了两件事——① 边缘输出**灰度梯度**而不是二值（`min(255,|gx|+|gy|)`），与本仓库 2026-11-12 的改动方向一致；② 全分辨率 3×3 + 同步读行缓存是这条路的标准做法。
