import csv
import queue
import socket
import sys
import threading
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from protocol import (
    ColorPacket,
    MODE_NAMES,
    MotionPacket,
    StatusPacket,
    encode_color_request,
    encode_mode,
    encode_motion_request,
    encode_status_request,
    parse_packet,
)


# Apple DESIGN.md tokens, adapted for a Windows/Tkinter monitoring console.
BG = "#f5f5f7"
CARD = "#ffffff"
PEARL = "#fafafc"
SIDEBAR = "#fbfbfd"
SIDEBAR_CARD = "#ffffff"
TEXT = "#1d1d1f"
MUTED = "#6e6e73"
BORDER = "#e0e0e0"
GLASS_SHADOW = "#e6e6ea"
GLASS_EDGE = "#e9e9ee"
ACCENT = "#0066cc"
ACCENT_HOVER = "#0071e3"
ACCENT_ON_DARK = "#2997ff"
SUCCESS = "#34c759"
WARNING = "#ff9f0a"
DANGER = "#ff3b30"
FONT = "Segoe UI Variable"


class UdpWorker(threading.Thread):
    def __init__(self, events: queue.Queue, fpga_ip="192.168.137.2", fpga_port=6002, local_port=6001):
        super().__init__(daemon=True)
        self.events = events
        self.fpga = (fpga_ip, fpga_port)
        self.local_port = local_port
        self.running = threading.Event()
        self.running.set()
        self.sock = None
        self.send_lock = threading.Lock()

    def run(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.sock.bind(("0.0.0.0", self.local_port))
            self.sock.settimeout(0.25)
            self.events.put(("listening", self.local_port))
        except OSError as exc:
            self.events.put(("error", f"无法监听 UDP {self.local_port}：{exc}"))
            return

        poll_started = time.monotonic()
        next_status_poll = poll_started
        next_color_poll = poll_started + 0.1
        next_motion_poll = poll_started + 0.15
        while self.running.is_set():
            now = time.monotonic()
            if now >= next_status_poll:
                self.send(encode_status_request())
                next_status_poll = now + 1.0
            if now >= next_color_poll:
                self.send(encode_color_request())
                next_color_poll = now + 0.1
            if now >= next_motion_poll:
                self.send(encode_motion_request())
                next_motion_poll = now + 0.1
            try:
                data, address = self.sock.recvfrom(2048)
            except socket.timeout:
                continue
            except OSError:
                break

            packet = parse_packet(data)
            if packet is None:
                self.events.put(("invalid", data, address))
            else:
                self.events.put(("packet", packet, address, time.monotonic()))

    def send(self, data: bytes):
        if self.sock is None:
            return
        try:
            with self.send_lock:
                self.sock.sendto(data, self.fpga)
        except OSError as exc:
            self.events.put(("error", f"UDP 发送失败：{exc}"))

    def set_mode(self, mode: int):
        self.send(encode_mode(mode))
        self.send(encode_status_request())

    def stop(self):
        self.running.clear()
        if self.sock is not None:
            self.sock.close()


class VisionConsole:
    def __init__(self, root: tk.Tk, start_network=True):
        self.root = root
        self.events = queue.Queue()
        self.worker = UdpWorker(self.events) if start_network else None
        self.last_rx = 0.0
        self.last_color_rx = 0.0
        self.started_at = time.monotonic()
        self.packet_count = 0
        self.alarm_count = 0
        self.current_mode = None
        self.current_blocks = None
        self.current_motion = None
        self.current_status = None
        self.last_detection_summary = None
        self.ever_connected = False
        self.seen_color_packet = False
        self.target_missing_since = None
        self.active_alarms = set()
        self.records = []
        self.mode_buttons = {}
        self.block_vars = {}

        self.connection_var = tk.StringVar(value="正在连接")
        self.connection_detail_var = tk.StringVar(value="等待 FPGA 状态帧")
        self.mode_var = tk.StringVar(value="--")
        self.fps_var = tk.StringVar(value="--")
        self.link_var = tk.StringVar(value="--")
        self.packet_var = tk.StringVar(value="0")
        self.frame_var = tk.StringVar(value="--")
        self.latency_var = tk.StringVar(value="--")
        self.motion_var = tk.StringVar(value="--")
        self.uptime_var = tk.StringVar(value="00:00:00")
        self.alarm_var = tk.StringVar(value="0")
        self.color_hint_var = tk.StringVar(value="等待 FPGA 色块数据")
        self.focus_var = tk.StringVar(value="全部")
        self.loss_seconds_var = tk.StringVar(value="2.0")
        self.min_fps_var = tk.StringVar(value="20")
        self.motion_limit_var = tk.StringVar(value="200")
        self.loss_seconds = 2.0
        self.min_fps = 20
        self.motion_limit = 200


        self._configure_window()
        self._build_ui()
        self._draw_tracker()
        self._log("系统", "上位机已启动，正在监听 UDP 6001。")

        if self.worker is not None:
            self.worker.start()
        self.root.after(100, self._poll_events)
        self.root.after(500, self._refresh_connection)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

    def _configure_window(self):
        self.root.title("FPGA Vision · 视觉遥测控制台")
        self.root.geometry("1440x900")
        self.root.minsize(1180, 720)
        self.root.configure(bg=BG)
        try:
            self.root.tk.call("tk", "scaling", 1.25)
        except tk.TclError:
            pass

    def _build_ui(self):
        self._build_sidebar()

        main = tk.Frame(self.root, bg=BG)
        main.pack(side="left", fill="both", expand=True)

        global_nav = tk.Frame(main, bg="#000000", height=44)
        global_nav.pack(fill="x")
        global_nav.pack_propagate(False)
        tk.Label(global_nav, text="●", bg="#000000", fg="white",
                 font=(FONT, 10)).pack(side="left", padx=(24, 8))
        tk.Label(global_nav, text="FPGA Vision", bg="#000000", fg="white",
                 font=(FONT, 10, "bold")).pack(side="left")
        tk.Label(global_nav, text="设备总览     目标监控     性能监控     远程控制",
                 bg="#000000", fg="#d2d2d7", font=(FONT, 9)).pack(side="left", padx=34)

        status = tk.Frame(global_nav, bg="#000000")
        status.pack(side="right", padx=24)
        self.header_dot = tk.Label(status, text="●", bg="#000000", fg=WARNING, font=(FONT, 11))
        self.header_dot.pack(side="left", padx=(0, 6))
        tk.Label(status, textvariable=self.connection_var, bg="#000000", fg="white",
                 font=(FONT, 9)).pack(side="left")

        subnav = tk.Frame(main, bg=BG, height=64, highlightbackground=BORDER, highlightthickness=1)
        subnav.pack(fill="x")
        subnav.pack_propagate(False)
        title_group = tk.Frame(subnav, bg=BG)
        title_group.pack(side="left", padx=26)
        tk.Label(title_group, text="视觉识别控制台", bg=BG, fg=TEXT,
                 font=(FONT, 17, "bold")).pack(anchor="w")
        tk.Label(title_group, text="设备端独立运行 · UDP 仅传输状态与识别数据",
                 bg=BG, fg=MUTED, font=(FONT, 8)).pack(anchor="w")
        tk.Label(subnav, text="纯数据遥测 · 无图像传输", bg=PEARL, fg=ACCENT,
                 font=(FONT, 9), padx=14, pady=7,
                 highlightbackground=BORDER, highlightthickness=1).pack(side="right", padx=24)

        body = tk.Frame(main, bg=BG)
        body.pack(fill="both", expand=True, padx=24, pady=22)
        body.grid_columnconfigure(0, weight=3)
        body.grid_columnconfigure(1, weight=2)
        body.grid_rowconfigure(1, weight=1)

        metrics = tk.Frame(body, bg=BG)
        metrics.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 16))
        for i in range(6):
            metrics.grid_columnconfigure(i, weight=1)
        self._metric(metrics, 0, "FPGA 模式", self.mode_var)
        self._metric(metrics, 1, "画面帧率", self.fps_var, " FPS")
        self._metric(metrics, 2, "累计帧号", self.frame_var)
        self._metric(metrics, 3, "处理延迟", self.latency_var, " 帧")
        self._metric(metrics, 4, "运动区域", self.motion_var)
        self._metric(metrics, 5, "接收包 / 告警", self.packet_var)

        left = tk.Frame(body, bg=BG)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, 8))
        left.grid_rowconfigure(0, weight=3)
        left.grid_rowconfigure(1, weight=2)
        left.grid_columnconfigure(0, weight=1)

        tracker_card, tracker_shell = self._card(left)
        tracker_shell.grid(row=0, column=0, sticky="nsew", pady=(0, 12))
        title_row = tk.Frame(tracker_card, bg=CARD)
        title_row.pack(fill="x", padx=18, pady=(16, 4))
        tk.Label(title_row, text="色块位置图", bg=CARD, fg=TEXT,
                 font=(FONT, 13, "bold")).pack(side="left")
        tk.Label(title_row, textvariable=self.color_hint_var, bg=CARD, fg=MUTED,
                 font=(FONT, 9)).pack(side="right")
        self.tracker = tk.Canvas(tracker_card, bg=PEARL, highlightthickness=0, height=330)
        self.tracker.pack(fill="both", expand=True, padx=14, pady=(6, 14))
        self.tracker.bind("<Configure>", lambda _event: self._draw_tracker())

        log_card, log_shell = self._card(left)
        log_shell.grid(row=1, column=0, sticky="nsew")
        log_head = tk.Frame(log_card, bg=CARD)
        log_head.pack(fill="x", padx=18, pady=(14, 6))
        tk.Label(log_head, text="交互记录", bg=CARD, fg=TEXT,
                 font=(FONT, 12, "bold")).pack(side="left")
        tk.Button(log_head, text="清空", command=self._clear_log, bg=CARD, fg=MUTED,
                  activebackground=CARD, activeforeground=TEXT, relief="flat",
                  cursor="hand2", font=(FONT, 9)).pack(side="right")
        tk.Button(log_head, text="导出 CSV", command=self._export_csv, bg=CARD, fg=ACCENT,
                  activebackground=CARD, activeforeground=ACCENT_HOVER, relief="flat",
                  cursor="hand2", font=(FONT, 9, "bold")).pack(side="right", padx=(0, 12))
        self.log_text = tk.Text(log_card, bg=CARD, fg=TEXT, relief="flat", borderwidth=0,
                                font=(FONT, 9), padx=16, pady=8, state="disabled",
                                wrap="word", spacing1=3, spacing3=8, height=6)
        self.log_text.pack(fill="both", expand=True, padx=2, pady=(0, 8))
        self.log_text.tag_configure("time", foreground="#86868b")
        self.log_text.tag_configure("system", foreground=ACCENT, font=(FONT, 9, "bold"))
        self.log_text.tag_configure("fpga", foreground="#004f9f", font=(FONT, 9, "bold"))
        self.log_text.tag_configure("host", foreground=TEXT, font=(FONT, 9, "bold"))
        self.log_text.tag_configure("alarm", foreground=DANGER, font=(FONT, 9, "bold"))

        right = tk.Frame(body, bg=BG)
        right.grid(row=1, column=1, sticky="nsew", padx=(8, 0))
        right.grid_columnconfigure(0, weight=1)

        info_card, info_shell = self._card(right)
        info_shell.pack(fill="x", pady=(0, 12))
        tk.Label(info_card, text="识别结果", bg=CARD, fg=TEXT,
                 font=(FONT, 13, "bold")).pack(anchor="w", padx=18, pady=(16, 10))
        for name, color in (("红色", "#ef4444"), ("绿色", "#22c55e"), ("蓝色", "#3b82f6")):
            self._block_row(info_card, name, color)
        tk.Label(info_card, text="坐标以 1280×720 画面为基准；X/Y 与尺寸为压缩遥测还原值。",
                 bg=CARD, fg=MUTED, font=(FONT, 8), wraplength=330,
                 justify="left").pack(anchor="w", padx=18, pady=(8, 15))

        control_card, control_shell = self._card(right)
        control_shell.pack(fill="x", pady=(0, 12))
        tk.Label(control_card, text="目标与监控参数", bg=CARD, fg=TEXT,
                 font=(FONT, 12, "bold")).pack(anchor="w", padx=18, pady=(14, 8))
        focus_row = tk.Frame(control_card, bg=CARD)
        focus_row.pack(fill="x", padx=18, pady=3)
        tk.Label(focus_row, text="监控目标", bg=CARD, fg=MUTED, font=(FONT, 9)).pack(side="left")
        focus_box = ttk.Combobox(focus_row, textvariable=self.focus_var, state="readonly",
                                 values=("全部", "红色", "绿色", "蓝色"), width=9)
        focus_box.pack(side="right")
        focus_box.bind("<<ComboboxSelected>>", lambda _event: self._focus_changed())
        self._parameter_row(control_card, "丢失告警 / 秒", self.loss_seconds_var)
        self._parameter_row(control_card, "最低帧率 / FPS", self.min_fps_var)
        self._parameter_row(control_card, "运动区域阈值", self.motion_limit_var)
        tk.Button(control_card, text="应用监控参数", command=self._apply_monitor_params,
                  bg=ACCENT, fg="white", activebackground=ACCENT_HOVER,
                  activeforeground="white", relief="flat", cursor="hand2",
                  font=(FONT, 10), padx=12, pady=9).pack(fill="x", padx=18, pady=(10, 16))

        network_card, network_shell = self._card(right)
        network_shell.pack(fill="x")
        tk.Label(network_card, text="网络信息", bg=CARD, fg=TEXT,
                 font=(FONT, 12, "bold")).pack(anchor="w", padx=18, pady=(15, 10))
        self._detail(network_card, "电脑监听", "0.0.0.0 : 6001")
        self._detail(network_card, "FPGA 目标", "192.168.137.2 : 6002")
        self._detail(network_card, "本机网卡", "192.168.137.1 / 24")
        self._detail_var(network_card, "PHY 链路", self.link_var)
        self._detail_var(network_card, "本次运行", self.uptime_var)
        self._detail_var(network_card, "累计告警", self.alarm_var)
        tk.Label(network_card, textvariable=self.connection_detail_var, bg=PEARL, fg=ACCENT,
                 font=(FONT, 9), padx=10, pady=8, anchor="w").pack(fill="x", padx=18, pady=(10, 16))

    def _build_sidebar(self):
        sidebar = tk.Frame(self.root, bg=SIDEBAR, width=244,
                           highlightbackground=BORDER, highlightthickness=1)
        sidebar.pack(side="left", fill="y")
        sidebar.pack_propagate(False)

        brand = tk.Frame(sidebar, bg=SIDEBAR)
        brand.pack(fill="x", padx=20, pady=(24, 20))
        icon = tk.Label(brand, text="◉", bg=SIDEBAR, fg=TEXT,
                        font=(FONT, 17, "bold"))
        icon.pack(side="left")
        brand_text = tk.Frame(brand, bg=SIDEBAR)
        brand_text.pack(side="left", padx=10)
        tk.Label(brand_text, text="设备控制", bg=SIDEBAR, fg=TEXT,
                 font=(FONT, 13, "bold")).pack(anchor="w")
        tk.Label(brand_text, text="192.168.137.2", bg=SIDEBAR, fg=MUTED,
                 font=(FONT, 8)).pack(anchor="w")

        connection = tk.Frame(sidebar, bg=SIDEBAR_CARD, padx=14, pady=12,
                              highlightbackground=BORDER, highlightthickness=1)
        connection.pack(fill="x", padx=14, pady=(0, 18))
        row = tk.Frame(connection, bg=SIDEBAR_CARD)
        row.pack(fill="x")
        self.sidebar_dot = tk.Label(row, text="●", bg=SIDEBAR_CARD, fg=WARNING, font=(FONT, 11))
        self.sidebar_dot.pack(side="left")
        tk.Label(row, textvariable=self.connection_var, bg=SIDEBAR_CARD, fg=TEXT,
                 font=(FONT, 10, "bold")).pack(side="left", padx=7)
        tk.Label(connection, text="UDP 6001 ↔ 6002", bg=SIDEBAR_CARD, fg=MUTED,
                 font=(FONT, 9)).pack(anchor="w", pady=(5, 0))

        tk.Label(sidebar, text="算法模式", bg=SIDEBAR, fg=MUTED,
                 font=(FONT, 9, "bold")).pack(anchor="w", padx=20, pady=(0, 9))
        for mode, name in MODE_NAMES.items():
            button = tk.Button(sidebar, text=f"{mode}    {name}", anchor="w",
                               command=lambda selected=mode: self._select_mode(selected),
                               bg=SIDEBAR, fg=TEXT, activebackground="#e8e8ed",
                               activeforeground=TEXT, relief="flat", bd=0,
                               padx=16, pady=11, cursor="hand2", font=(FONT, 10))
            button.pack(fill="x", padx=10, pady=2)
            self.mode_buttons[mode] = button

        spacer = tk.Frame(sidebar, bg=SIDEBAR)
        spacer.pack(fill="both", expand=True)
        tk.Label(sidebar, text="设备独立运行 · UDP 仅监控管理", bg=SIDEBAR, fg=MUTED,
                 font=(FONT, 8)).pack(pady=(0, 6))
        tk.Label(sidebar, text="v2.1 · Apple UI · 不传输图像", bg=SIDEBAR, fg="#86868b",
                 font=(FONT, 8)).pack(pady=(0, 18))

    def _metric(self, parent, column, title, variable, suffix=""):
        card, shell = self._card(parent)
        shell.grid(row=0, column=column, sticky="ew", padx=(0 if column == 0 else 4, 0 if column == 5 else 4))
        tk.Label(card, text=title, bg=CARD, fg=MUTED, font=(FONT, 9)).pack(anchor="w", padx=16, pady=(14, 3))
        row = tk.Frame(card, bg=CARD)
        row.pack(anchor="w", padx=16, pady=(0, 14))
        tk.Label(row, textvariable=variable, bg=CARD, fg=TEXT,
                 font=(FONT, 17, "bold")).pack(side="left")
        if suffix:
            tk.Label(row, text=suffix, bg=CARD, fg=MUTED, font=(FONT, 9)).pack(side="left", pady=(6, 0))

    @staticmethod
    def _card(parent):
        shell = tk.Frame(parent, bg=BG)
        shadow = tk.Frame(shell, bg=GLASS_SHADOW)
        shadow.place(x=3, y=5, relwidth=1.0, relheight=1.0)
        card = tk.Frame(shell, bg=CARD, highlightbackground=GLASS_EDGE, highlightthickness=1)
        card.pack(fill="both", expand=True)
        return card, shell

    def _block_row(self, parent, name, color):
        row = tk.Frame(parent, bg=PEARL, highlightbackground=BORDER, highlightthickness=1)
        row.pack(fill="x", padx=18, pady=4)
        tk.Label(row, text="●", bg=PEARL, fg=color, font=(FONT, 14)).pack(side="left", padx=(12, 8), pady=11)
        tk.Label(row, text=name, bg=PEARL, fg=TEXT, width=5,
                 font=(FONT, 10, "bold"), anchor="w").pack(side="left")
        value = tk.StringVar(value="未收到数据")
        self.block_vars[name] = value
        tk.Label(row, textvariable=value, bg=PEARL, fg=MUTED,
                 font=(FONT, 9), anchor="e").pack(side="right", padx=12)

    @staticmethod
    def _detail(parent, key, value):
        row = tk.Frame(parent, bg=CARD)
        row.pack(fill="x", padx=18, pady=3)
        tk.Label(row, text=key, bg=CARD, fg=MUTED, font=(FONT, 9)).pack(side="left")
        tk.Label(row, text=value, bg=CARD, fg=TEXT, font=(FONT, 9)).pack(side="right")

    @staticmethod
    def _detail_var(parent, key, variable):
        row = tk.Frame(parent, bg=CARD)
        row.pack(fill="x", padx=18, pady=3)
        tk.Label(row, text=key, bg=CARD, fg=MUTED, font=(FONT, 9)).pack(side="left")
        tk.Label(row, textvariable=variable, bg=CARD, fg=TEXT,
                 font=(FONT, 9)).pack(side="right")

    @staticmethod
    def _parameter_row(parent, key, variable):
        row = tk.Frame(parent, bg=CARD)
        row.pack(fill="x", padx=18, pady=3)
        tk.Label(row, text=key, bg=CARD, fg=MUTED, font=(FONT, 9)).pack(side="left")
        tk.Entry(row, textvariable=variable, width=10, justify="right", bg=PEARL,
                 fg=TEXT, relief="flat", borderwidth=0, highlightthickness=1,
                 highlightbackground=BORDER, highlightcolor=ACCENT,
                 font=(FONT, 9)).pack(side="right", ipady=4)

    def _select_mode(self, mode):
        if self.worker is None:
            return
        self.worker.set_mode(mode)
        self._highlight_mode(mode)
        self._log("上位机", f"请求切换到模式 {mode} · {MODE_NAMES[mode]}")

    def _focus_changed(self):
        self.target_missing_since = None
        self._set_alarm("target_lost", False, "目标恢复")
        self._draw_tracker()
        self._log("上位机", f"监控目标切换为：{self.focus_var.get()}（仅影响上位机显示与告警）")

    def _apply_monitor_params(self):
        try:
            loss_seconds = float(self.loss_seconds_var.get())
            min_fps = int(self.min_fps_var.get())
            motion_limit = int(self.motion_limit_var.get())
            if not 0.5 <= loss_seconds <= 60 or not 0 <= min_fps <= 240 or not 0 <= motion_limit <= 32767:
                raise ValueError
        except ValueError:
            messagebox.showwarning("参数无效", "丢失时长应为 0.5~60 秒，帧率为 0~240，运动阈值为 0~32767。")
            return
        self.loss_seconds = loss_seconds
        self.min_fps = min_fps
        self.motion_limit = motion_limit
        self._log("上位机", "监控告警参数已应用；这些参数不改变 FPGA 识别算法。")
        self._evaluate_alarms(time.monotonic())

    def _poll_events(self):
        try:
            while True:
                event = self.events.get_nowait()
                kind = event[0]
                if kind == "packet":
                    self._handle_packet(event[1], event[2], event[3])
                elif kind == "listening":
                    self._log("系统", f"UDP {event[1]} 端口监听成功。")
                elif kind == "invalid":
                    self._log("系统", f"忽略未知数据帧：{event[1].hex(' ').upper()}")
                elif kind == "error":
                    self._log("系统", event[1])
                    messagebox.showerror("网络错误", event[1])
        except queue.Empty:
            pass
        self.root.after(100, self._poll_events)

    def _handle_packet(self, packet, address, received_at):
        was_disconnected = received_at - self.last_rx > 3.0
        self.last_rx = received_at
        self.ever_connected = True
        self.packet_count += 1
        self.packet_var.set(f"{self.packet_count} / {self.alarm_count}")

        if was_disconnected:
            self._log("FPGA", f"已连接 {address[0]}:{address[1]}")

        if isinstance(packet, StatusPacket):
            self.current_status = packet
            old_mode = self.current_mode
            self.current_mode = packet.mode
            self.mode_var.set(f"{packet.mode} · {MODE_NAMES[packet.mode]}")
            self.fps_var.set(str(packet.fps))
            self.link_var.set("已连接" if packet.link else "已断开")
            self.frame_var.set("--" if packet.frame_count is None else str(packet.frame_count))
            self.latency_var.set("--" if packet.latency_frames is None else str(packet.latency_frames))
            self.motion_var.set("--" if packet.motion_count is None else str(packet.motion_count))
            self._highlight_mode(packet.mode)
            if old_mode is not None and old_mode != packet.mode:
                self._log("FPGA", f"模式已切换为 {packet.mode} · {MODE_NAMES[packet.mode]}")
        elif isinstance(packet, ColorPacket):
            self.current_blocks = packet.blocks
            self.last_color_rx = received_at
            self.seen_color_packet = True
            self.color_hint_var.set("实时 UDP 色块帧")
            self._update_blocks()
            self._draw_tracker()

            summary = tuple(block.detected for block in packet.blocks)
            if summary != self.last_detection_summary:
                found = "、".join(block.name for block in packet.blocks if block.detected) or "无"
                self._log("FPGA", f"识别目标：{found}")
                self.last_detection_summary = summary
        elif isinstance(packet, MotionPacket):
            self.current_motion = packet.box
            self._draw_tracker()
        self._evaluate_alarms(received_at)

    def _refresh_connection(self):
        now = time.monotonic()
        connected = now - self.last_rx < 3.0
        elapsed = int(now - self.started_at)
        self.uptime_var.set(f"{elapsed // 3600:02d}:{elapsed % 3600 // 60:02d}:{elapsed % 60:02d}")
        if connected:
            self.connection_var.set("已连接")
            self.connection_detail_var.set("UDP 通信正常，正在周期读取状态")
            color = SUCCESS
        else:
            self.connection_var.set("等待连接")
            self.connection_detail_var.set("未收到状态；请检查供电、网线和 FPGA bit")
            color = WARNING
        self.header_dot.configure(fg=color)
        self.sidebar_dot.configure(fg=color)

        if self.last_color_rx and now - self.last_color_rx >= 3.0:
            self.color_hint_var.set("色块数据已暂停")

        self._evaluate_alarms(now)
        self.root.after(500, self._refresh_connection)

    def _evaluate_alarms(self, now):
        connected = now - self.last_rx < 3.0
        self._set_alarm("network", self.ever_connected and not connected,
                        "网络通信中断超过 3 秒", "网络通信已恢复")

        status = self.current_status
        status_fresh = status is not None and connected
        self._set_alarm("fps", status_fresh and self.min_fps > 0 and status.fps < self.min_fps,
                        f"视频帧率低于 {self.min_fps} FPS", "视频帧率恢复正常")
        motion = None if status is None else status.motion_count
        self._set_alarm("motion", status_fresh and motion is not None and motion > self.motion_limit,
                        f"运动区域超过阈值 {self.motion_limit}", "运动区域恢复正常")

        missing = False
        if self.seen_color_packet and connected and self.current_blocks:
            selected = self.focus_var.get()
            candidates = tuple(self.current_blocks) if selected == "全部" else tuple(
                block for block in self.current_blocks if block.name == selected
            )
            missing = not any(block.detected for block in candidates)
        if missing:
            if self.target_missing_since is None:
                self.target_missing_since = now
        else:
            self.target_missing_since = None
        lost = self.target_missing_since is not None and now - self.target_missing_since >= self.loss_seconds
        self._set_alarm("target_lost", lost,
                        f"{self.focus_var.get()}目标连续丢失超过 {self.loss_seconds:g} 秒", "目标重新识别")

    def _set_alarm(self, key, active, message, recovery="告警已恢复"):
        if active and key not in self.active_alarms:
            self.active_alarms.add(key)
            self.alarm_count += 1
            self.alarm_var.set(str(self.alarm_count))
            self.packet_var.set(f"{self.packet_count} / {self.alarm_count}")
            self._log("告警", message)
        elif not active and key in self.active_alarms:
            self.active_alarms.remove(key)
            self._log("系统", recovery)

    def _highlight_mode(self, active_mode):
        for mode, button in self.mode_buttons.items():
            if mode == active_mode:
                button.configure(text=f"{mode}    {MODE_NAMES[mode]}  ▸",
                                 bg=ACCENT, fg="white", activebackground=ACCENT_HOVER,
                                 activeforeground="white")
                button.pack_configure(padx=(10, 0))
            else:
                button.configure(text=f"{mode}    {MODE_NAMES[mode]}",
                                 bg=SIDEBAR, fg=TEXT, activebackground="#e8e8ed",
                                 activeforeground=TEXT)
                button.pack_configure(padx=10)

    def _update_blocks(self):
        for block in self.current_blocks or ():
            if block.detected:
                side = "左" if block.deviation < 0 else "右" if block.deviation > 0 else "中"
                y_text = "--" if block.center_y is None else block.center_y
                text = f"有效 · X={block.center_x} Y={y_text} · W={block.width} · {side}{abs(block.deviation * 8)}"
            else:
                text = "本帧未识别"
            self.block_vars[block.name].set(text)

    def _draw_tracker(self):
        if not hasattr(self, "tracker"):
            return
        canvas = self.tracker
        canvas.delete("all")
        width = canvas.winfo_width()
        height = canvas.winfo_height()
        if width < 240 or height < 120:
            return
        x0, x1 = 56, width - 24
        y0, y1 = 38, height - 34

        canvas.create_rectangle(1, 1, width - 1, height - 1, outline="#f0f0f0", fill=PEARL)
        canvas.create_rectangle(x0, y0, x1, y1, outline=BORDER, width=2)
        center_x = x0 + (x1 - x0) / 2
        center_y = y0 + (y1 - y0) / 2
        canvas.create_line(center_x, y0, center_x, y1, fill="#c7c7cc", dash=(5, 4))
        canvas.create_line(x0, center_y, x1, center_y, fill="#e5e5ea", dash=(5, 4))
        canvas.create_text(center_x, 18, text="FPGA 识别坐标图 · 1280 × 720", fill=MUTED, font=(FONT, 9))
        canvas.create_text(x0, y1 + 16, text="(0,720)", fill="#86868b",
                           font=(FONT, 8), anchor="w")
        canvas.create_text(x1, y1 + 16, text="(1280,720)", fill="#86868b",
                           font=(FONT, 8), anchor="e")

        names = (("红色", "#ef4444"), ("绿色", "#22c55e"), ("蓝色", "#3b82f6"))
        block_map = {block.name: block for block in self.current_blocks or ()}
        selected = self.focus_var.get()
        for index, (name, color) in enumerate(names):
            block = block_map.get(name)
            if block and block.detected:
                plot_width = x1 - x0
                cx = x0 + (block.center_x / 1279) * plot_width
                source_y = block.center_y if block.center_y is not None else (index + 1) * 180
                cy = y0 + (source_y / 719) * (y1 - y0)
                marker_width = min(plot_width, max(12, (block.width / 1280) * plot_width))
                cx = min(max(cx, x0 + marker_width / 2), x1 - marker_width / 2)
                cy = min(max(cy, y0 + 13), y1 - 13)
                outline_width = 4 if selected in ("全部", name) else 1
                canvas.create_rectangle(cx - marker_width / 2, cy - 13, cx + marker_width / 2, cy + 13,
                                        fill=color, outline="#111827", width=outline_width)
                label_width = min(210, plot_width - 16)
                label_x = min(max(cx, x0 + label_width / 2), x1 - label_width / 2)
                label_y = cy - 25 if cy > y0 + 40 else cy + 25
                canvas.create_text(label_x, label_y,
                                   text=f"{name}  ({block.center_x},{source_y})  W={block.width}",
                                   fill=color, font=(FONT, 8, "bold"), width=label_width)

        if self.current_motion is not None and self.current_motion.detected:
            box = self.current_motion
            ml = x0 + (box.left / 1279) * (x1 - x0)
            mr = x0 + (box.right / 1279) * (x1 - x0)
            mt = y0 + (box.top / 719) * (y1 - y0)
            mbb = y0 + (box.bottom / 719) * (y1 - y0)
            ml, mr = min(max(ml, x0), x1), min(max(mr, x0), x1)
            mt, mbb = min(max(mt, y0), y1), min(max(mbb, y0), y1)
            canvas.create_rectangle(ml, mt, mr, mbb, outline=WARNING, width=2, dash=(6, 4))
            label_y = mt - 9 if mt > y0 + 20 else mbb + 13
            canvas.create_text(ml, label_y, text=f"运动区域  {box.motion_count}",
                               fill=WARNING, font=(FONT, 9, "bold"), anchor="w")

        if self.current_blocks is None:
            hint_title = "等待 FPGA 上报色块帧"
            hint_sub = "请下载新版 telemetry bit；旧版 bit 只会上报状态，不会上报色块"
        else:
            hint_title = None
        if hint_title is not None:
            message_left, message_right = x0 + 20, x1 - 20
            canvas.create_rectangle(message_left, height / 2 - 38,
                                    message_right, height / 2 + 38,
                                    fill="#ffffff", outline=BORDER)
            canvas.create_text((message_left + message_right) / 2, height / 2 - 10,
                               text=hint_title, fill=TEXT, font=(FONT, 11, "bold"))
            canvas.create_text((message_left + message_right) / 2, height / 2 + 16,
                               text=hint_sub, fill=MUTED, font=(FONT, 8),
                               width=message_right - message_left - 20)

    def _log(self, source, message):
        if not hasattr(self, "log_text"):
            return
        tag = {"系统": "system", "FPGA": "fpga", "上位机": "host", "告警": "alarm"}.get(source, "system")
        timestamp = time.strftime("%H:%M:%S")
        self.records.append((time.strftime("%Y-%m-%d %H:%M:%S"), source, message))
        self.log_text.configure(state="normal")
        self.log_text.insert("end", f"{timestamp}  ", "time")
        self.log_text.insert("end", f"{source}\n", tag)
        self.log_text.insert("end", f"{message}\n")
        self.log_text.configure(state="disabled")
        self.log_text.see("end")

    def _clear_log(self):
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="disabled")

    def _export_csv(self):
        path = filedialog.asksaveasfilename(
            title="导出运行记录",
            defaultextension=".csv",
            filetypes=(("CSV 文件", "*.csv"),),
            initialfile=time.strftime("FPGA运行记录_%Y%m%d_%H%M%S.csv"),
        )
        if not path:
            return
        try:
            with open(path, "w", newline="", encoding="utf-8-sig") as handle:
                writer = csv.writer(handle)
                writer.writerow(("时间", "类别", "内容"))
                writer.writerows(self.records)
                writer.writerow(())
                writer.writerow(("任务统计", "接收包", self.packet_count))
                writer.writerow(("任务统计", "累计告警", self.alarm_count))
                writer.writerow(("任务统计", "运行时长", self.uptime_var.get()))
                if self.current_status is not None:
                    writer.writerow(("当前状态", "模式", MODE_NAMES[self.current_status.mode]))
                    writer.writerow(("当前状态", "FPS", self.current_status.fps))
                    writer.writerow(("当前状态", "累计帧号", self.current_status.frame_count))
                    writer.writerow(("当前状态", "处理延迟/帧", self.current_status.latency_frames))
                    writer.writerow(("当前状态", "运动区域", self.current_status.motion_count))
            self._log("系统", f"数据已导出：{path}")
        except OSError as exc:
            messagebox.showerror("导出失败", str(exc))

    def close(self):
        if self.worker is not None:
            self.worker.stop()
        self.root.destroy()


def main():
    self_test = "--self-test-ui" in sys.argv
    root = tk.Tk()
    app = VisionConsole(root, start_network=not self_test)
    if self_test:
        root.geometry("1180x720")
        root.update_idletasks()
        root.update()
        assert root.winfo_width() >= 1050
        assert len(app.mode_buttons) == 5
        assert len(app.block_vars) == 3
        app._draw_tracker()
        tracker_bounds = app.tracker.bbox("all")
        assert tracker_bounds is not None
        assert tracker_bounds[0] >= 0 and tracker_bounds[2] <= app.tracker.winfo_width()
        assert tracker_bounds[1] >= 0 and tracker_bounds[3] <= app.tracker.winfo_height()
        edge_packet = parse_packet(bytes((0xAB, 0x81, 40, 0, 0, 40, 90, 79, 40, 179, 0x55)))
        assert isinstance(edge_packet, ColorPacket)
        app.current_blocks = edge_packet.blocks
        app._draw_tracker()
        assert app.tracker.bbox("all") == tracker_bounds
        app._highlight_mode(3)
        assert app.mode_buttons[3].cget("text").endswith("▸")
        assert not app.mode_buttons[1].cget("text").endswith("▸")
        print("PASS: UI created and tracker fits at minimum window size")
        app.close()
        return
    root.mainloop()


if __name__ == "__main__":
    main()
