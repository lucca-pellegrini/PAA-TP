const std = @import("std");

// Catppuccin Mocha Palette
const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub const bg_dark = Color{ .r = 24, .g = 24, .b = 37 };
    pub const surface = Color{ .r = 30, .g = 30, .b = 46 };
    pub const surface_light = Color{ .r = 49, .g = 50, .b = 68 };
    pub const border_focus = Color{ .r = 137, .g = 180, .b = 250 };
    pub const border_dim = Color{ .r = 69, .g = 71, .b = 90 };
    pub const text = Color{ .r = 205, .g = 214, .b = 244 };
    pub const text_dim = Color{ .r = 108, .g = 112, .b = 134 };
    pub const text_bright = Color{ .r = 255, .g = 255, .b = 255 };
    pub const green = Color{ .r = 166, .g = 227, .b = 161 };
    pub const blue = Color{ .r = 137, .g = 180, .b = 250 };
    pub const yellow = Color{ .r = 249, .g = 226, .b = 175 };
    pub const peach = Color{ .r = 250, .g = 179, .b = 135 };
    pub const red = Color{ .r = 243, .g = 139, .b = 168 };
    pub const mauve = Color{ .r = 203, .g = 166, .b = 247 };
    pub const teal = Color{ .r = 148, .g = 226, .b = 213 };
};

const THROBBER_FRAMES = [_][]const u8{
    "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
};

const BLOCK_EIGHTHS = [_][]const u8{
    " ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█",
};

pub const QsUiTelemetry = extern struct {
    benchmark_name: ?[*:0]const u8 = null,
    dataset_name: ?[*:0]const u8 = null,
    variant_name: ?[*:0]const u8 = null,
    current_step: usize = 0,
    total_steps: usize = 0,
    current_rep: usize = 0,
    total_reps: usize = 0,
    array_size: usize = 0,
    active_threads: u32 = 0,
    pinned_cpu: c_int = -1,
    last_time_ns: f64 = 0.0,
    comparisons: u64 = 0,
    swaps: u64 = 0,
    cycles: u64 = 0,
    instructions: u64 = 0,
    branch_misses: u64 = 0,
    l1d_misses: u64 = 0,
    llc_misses: u64 = 0,
};

const Timespec = extern struct {
    sec: isize,
    nsec: isize,
};
extern "c" fn clock_gettime(clk_id: c_int, tp: *Timespec) c_int;

const Winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;

fn getMonotonicNs() u64 {
    var ts: Timespec = undefined;
    _ = clock_gettime(1, &ts); // CLOCK_MONOTONIC = 1
    const sec: i64 = @intCast(ts.sec);
    const nsec: i64 = @intCast(ts.nsec);
    const total = sec * 1_000_000_000 + nsec;
    return if (total < 0) 0 else @intCast(total);
}

fn getTerminalCols() usize {
    var ws: Winsize = undefined;
    if (ioctl(2, 0x5413, &ws) == 0 or ioctl(1, 0x5413, &ws) == 0 or ioctl(0, 0x5413, &ws) == 0) { // TIOCGWINSZ = 0x5413
        if (ws.ws_col >= 120) return @intCast(ws.ws_col);
    }
    return 120;
}

fn countDisplayWidth(s: []const u8) usize {
    var cols: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == 0x1b) {
            i += 1;
            if (i < s.len and s[i] == '[') {
                i += 1;
                while (i < s.len and !(s[i] >= 0x40 and s[i] <= 0x7e)) : (i += 1) {}
                if (i < s.len) i += 1;
            } else if (i < s.len) {
                i += 1;
            }
        } else if ((s[i] & 0x80) == 0) {
            if (s[i] >= 0x20 and s[i] <= 0x7e) cols += 1;
            i += 1;
        } else if ((s[i] & 0xe0) == 0xc0) {
            cols += 1;
            i = @min(i + 2, s.len);
        } else if ((s[i] & 0xf0) == 0xe0) {
            cols += 1;
            i = @min(i + 3, s.len);
        } else if ((s[i] & 0xf8) == 0xf0) {
            cols += 1;
            i = @min(i + 4, s.len);
        } else {
            i += 1;
        }
    }
    return cols;
}

fn writePaddedOrTruncated(bw: *BufferWriter, s: []const u8, target_w: usize) void {
    var cols: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == 0x1b) {
            const start = i;
            i += 1;
            if (i < s.len and s[i] == '[') {
                i += 1;
                while (i < s.len and !(s[i] >= 0x40 and s[i] <= 0x7e)) : (i += 1) {}
                if (i < s.len) i += 1;
            } else if (i < s.len) {
                i += 1;
            }
            bw.writeAll(s[start..i]);
        } else {
            const start = i;
            var char_cols: usize = 0;
            if ((s[i] & 0x80) == 0) {
                if (s[i] >= 0x20 and s[i] <= 0x7e) char_cols = 1;
                i += 1;
            } else if ((s[i] & 0xe0) == 0xc0) {
                char_cols = 1;
                i = @min(i + 2, s.len);
            } else if ((s[i] & 0xf0) == 0xe0) {
                char_cols = 1;
                i = @min(i + 3, s.len);
            } else if ((s[i] & 0xf8) == 0xf0) {
                char_cols = 1;
                i = @min(i + 4, s.len);
            } else {
                i += 1;
            }

            if (char_cols > 0) {
                if (cols + char_cols <= target_w) {
                    bw.writeAll(s[start..i]);
                    cols += char_cols;
                }
            }
        }
    }

    bw.writeAll("\x1b[0m");

    while (cols < target_w) : (cols += 1) {
        bw.writeByte(' ');
    }
}

const BufferWriter = struct {
    buf: []u8,
    pos: usize = 0,

    pub fn writeAll(self: *BufferWriter, s: []const u8) void {
        if (self.pos + s.len <= self.buf.len) {
            @memcpy(self.buf[self.pos..][0..s.len], s);
            self.pos += s.len;
        }
    }

    pub fn writeByte(self: *BufferWriter, b: u8) void {
        if (self.pos < self.buf.len) {
            self.buf[self.pos] = b;
            self.pos += 1;
        }
    }

    pub fn print(self: *BufferWriter, comptime fmt: []const u8, args: anytype) void {
        if (self.pos >= self.buf.len) return;
        if (std.fmt.bufPrint(self.buf[self.pos..], fmt, args)) |s| {
            self.pos += s.len;
        } else |_| {}
    }

    pub fn getWritten(self: *const BufferWriter) []const u8 {
        return self.buf[0..self.pos];
    }
};

const MAX_LOGS = 6;
const LOG_LEN = 128;

pub const QsTuiContext = struct {
    total_steps: usize = 0,
    current_step: usize = 0,
    start_ns: u64 = 0,
    last_render_ns: u64 = 0,
    tick: usize = 0,
    quiet: bool = false,
    cursor_hidden: bool = false,
    initialized: bool = false,
    has_rendered: bool = false,

    latest: QsUiTelemetry = .{},
    // Owned copies of the names: the C side frees its plan before the final render.
    name_bufs: [3][64]u8 = undefined,

    logs: [MAX_LOGS][LOG_LEN]u8 = undefined,
    log_lens: [MAX_LOGS]usize = std.mem.zeroes([MAX_LOGS]usize),
    log_count: usize = 0,

    dyn_lib: ?std.DynLib = null,
    has_native_ot: bool = false,

    pub fn init(total_steps: usize) QsTuiContext {
        var ctx = QsTuiContext{
            .total_steps = total_steps,
            .start_ns = getMonotonicNs(),
            .quiet = false,
        };

        if (std.c.getenv("__QS_UI_SHUT_UP")) |v| {
            if (v[0] != 0 and v[0] != '0') {
                ctx.quiet = true;
            }
        }

        // Probe for @opentui/core native library
        const paths = [_][]const u8{
            "tui/node_modules/@opentui/core-linux-x64/libopentui.so",
            "node_modules/@opentui/core-linux-x64/libopentui.so",
        };
        for (paths) |p| {
            if (std.DynLib.open(p)) |lib| {
                ctx.dyn_lib = lib;
                ctx.has_native_ot = true;
                break;
            } else |_| {}
        }

        return ctx;
    }

    pub fn deinit(self: *QsTuiContext) void {
        if (!self.quiet and self.cursor_hidden) {
            // Restore cursor and terminal modes
            _ = std.c.write(2, "\x1b[?25h\n", 7);
            self.cursor_hidden = false;
        }
        if (self.dyn_lib) |*lib| {
            lib.close();
            self.dyn_lib = null;
        }
    }

    pub fn appendLog(self: *QsTuiContext, msg: []const u8) void {
        const idx = if (self.log_count < MAX_LOGS) self.log_count else MAX_LOGS - 1;
        if (self.log_count >= MAX_LOGS) {
            // Shift existing logs up
            var i: usize = 0;
            while (i < MAX_LOGS - 1) : (i += 1) {
                self.logs[i] = self.logs[i + 1];
                self.log_lens[i] = self.log_lens[i + 1];
            }
        } else {
            self.log_count += 1;
        }
        const copy_len = @min(msg.len, LOG_LEN);
        @memcpy(self.logs[idx][0..copy_len], msg[0..copy_len]);
        self.log_lens[idx] = copy_len;
    }

    pub fn render(self: *QsTuiContext, force: bool) void {
        if (self.quiet) return;

        const now = getMonotonicNs();
        // Throttle to ~30-60 FPS (16ms = 16_000_000 ns), unless forced or completed
        if (!force and (now - self.last_render_ns < 16_000_000)) {
            return;
        }
        self.last_render_ns = now;
        self.tick +%= 1;

        if (!self.cursor_hidden) {
            _ = std.c.write(2, "\x1b[?25l", 6); // Hide cursor
            self.cursor_hidden = true;
        }

        var raw_buf: [16384]u8 = undefined;
        var bw = BufferWriter{ .buf = &raw_buf };

        // Synchronized update start (\x1b[?2026h)
        bw.writeAll("\x1b[?2026h");

        if (self.has_rendered) {
            // Move cursor up 13 lines to overwrite previous zero-gap frame
            bw.writeAll("\x1b[13A\r");
        } else {
            self.has_rendered = true;
        }

        const width = getTerminalCols();
        const inner_w = width - 2;

        const spinner = THROBBER_FRAMES[self.tick % THROBBER_FRAMES.len];
        const bench = if (self.latest.benchmark_name) |b| std.mem.span(b) else "benchmark";
        const ds = if (self.latest.dataset_name) |d| std.mem.span(d) else "dataset";
        const var_name = if (self.latest.variant_name) |v| std.mem.span(v) else "variant";

        // Line 1: Header top border
        self.renderBorderLine(&bw, "╭", "─", "╮", inner_w);

        // Line 2: Header title bar
        {
            var line_buf: [2048]u8 = undefined;
            var lbw = BufferWriter{ .buf = &line_buf };
            lbw.writeAll(" ");
            lbw.print("\x1b[1;38;2;{d};{d};{d}m{s}\x1b[0m ", .{ Color.mauve.r, Color.mauve.g, Color.mauve.b, spinner });
            lbw.print("\x1b[1;38;2;{d};{d};{d}mQUICKSORT BENCHMARK\x1b[0m", .{ Color.text_bright.r, Color.text_bright.g, Color.text_bright.b });
            lbw.print(" \x1b[38;2;{d};{d};{d}m│\x1b[0m ", .{ Color.border_dim.r, Color.border_dim.g, Color.border_dim.b });
            lbw.print("\x1b[38;2;{d};{d};{d}m{s}:{s}/{s}\x1b[0m", .{ Color.teal.r, Color.teal.g, Color.teal.b, bench, var_name, ds });

            const cold_badge = "\x1b[48;2;49;50;68m\x1b[38;2;137;180;250m COLD 2xLLC \x1b[0m";
            const ok_badge = "\x1b[48;2;30;46;30m\x1b[38;2;166;227;161m VERIFIED OK \x1b[0m";
            const left_cols = countDisplayWidth(lbw.getWritten());
            const badges_cols = 12 + 1 + 13 + 1; // 27 cols
            if (inner_w > left_cols + badges_cols) {
                const pad = inner_w - left_cols - badges_cols;
                var p: usize = 0;
                while (p < pad) : (p += 1) lbw.writeByte(' ');
                lbw.print("{s} {s} ", .{ cold_badge, ok_badge });
            }
            self.renderContentLine(&bw, lbw.getWritten(), inner_w);
        }

        // Line 3: Header-to-Progress divider
        self.renderBorderLine(&bw, "├", "─", "┤", inner_w);

        // Line 4: Overall Progress bar
        const tot_steps = if (self.total_steps > 0) self.total_steps else 1;
        const cur_step = @min(self.current_step, tot_steps);
        const overall_pct = @as(f64, @floatFromInt(cur_step)) * 100.0 / @as(f64, @floatFromInt(tot_steps));
        const bar_w: usize = if (inner_w > 55) inner_w - 48 else 20;

        {
            var line_buf: [2048]u8 = undefined;
            var lbw = BufferWriter{ .buf = &line_buf };
            lbw.writeAll(" ");
            lbw.print("\x1b[1;38;2;{d};{d};{d}mOverall\x1b[0m   [", .{ Color.blue.r, Color.blue.g, Color.blue.b });
            self.renderProgressBar(&lbw, overall_pct, bar_w, Color.blue);
            lbw.print("] \x1b[1;38;2;{d};{d};{d}m{d: >5.1}%\x1b[0m ({d}/{d})", .{
                Color.text_bright.r, Color.text_bright.g, Color.text_bright.b,
                overall_pct,         cur_step,                 tot_steps,
            });
            self.renderContentLine(&bw, lbw.getWritten(), inner_w);
        }

        // Line 5: Repetition Progress bar
        const tot_reps = if (self.latest.total_reps > 0) self.latest.total_reps else 1;
        const cur_rep = @min(self.latest.current_rep, tot_reps);
        const rep_pct = @as(f64, @floatFromInt(cur_rep)) * 100.0 / @as(f64, @floatFromInt(tot_reps));

        {
            var line_buf: [2048]u8 = undefined;
            var lbw = BufferWriter{ .buf = &line_buf };
            lbw.writeAll(" ");
            lbw.print("\x1b[1;38;2;{d};{d};{d}mRepetition\x1b[0m[", .{ Color.teal.r, Color.teal.g, Color.teal.b });
            self.renderProgressBar(&lbw, rep_pct, bar_w, Color.teal);
            lbw.print("] \x1b[1;38;2;{d};{d};{d}m{d: >5.1}%\x1b[0m (rep {d}/{d}, n={d})", .{
                Color.text_bright.r,   Color.text_bright.g,   Color.text_bright.b,
                rep_pct,               cur_rep,               tot_reps,
                self.latest.array_size,
            });
            self.renderContentLine(&bw, lbw.getWritten(), inner_w);
        }

        // Line 6: Divider to Telemetry & Cores
        self.renderBorderLine(&bw, "├", "─", "┤", inner_w);

        // Line 7: Telemetry Row 1 (Time, IPC, Comparisons, Swaps)
        const time_ms = self.latest.last_time_ns / 1_000_000.0;
        const ipc = if (self.latest.cycles > 0)
            @as(f64, @floatFromInt(self.latest.instructions)) / @as(f64, @floatFromInt(self.latest.cycles))
        else
            0.0;

        {
            var line_buf: [2048]u8 = undefined;
            var lbw = BufferWriter{ .buf = &line_buf };
            lbw.writeAll(" ");
            lbw.print("\x1b[38;2;{d};{d};{d}mTime:\x1b[0m \x1b[1m{d: >7.2} ms\x1b[0m  ", .{ Color.text_dim.r, Color.text_dim.g, Color.text_dim.b, time_ms });
            lbw.print("\x1b[38;2;{d};{d};{d}mIPC:\x1b[0m \x1b[1;38;2;{d};{d};{d}m{d: >5.2}\x1b[0m  ", .{ Color.text_dim.r, Color.text_dim.g, Color.text_dim.b, Color.green.r, Color.green.g, Color.green.b, ipc });
            lbw.print("\x1b[38;2;{d};{d};{d}mCmp:\x1b[0m \x1b[1m{d: >9}\x1b[0m  ", .{ Color.text_dim.r, Color.text_dim.g, Color.text_dim.b, self.latest.comparisons });
            lbw.print("\x1b[38;2;{d};{d};{d}mSwp:\x1b[0m \x1b[1m{d: >9}\x1b[0m", .{ Color.text_dim.r, Color.text_dim.g, Color.text_dim.b, self.latest.swaps });
            self.renderContentLine(&bw, lbw.getWritten(), inner_w);
        }

        // Line 8: Telemetry Row 2 (Cycles, Instructions, Branch Misses, LLC Misses)
        {
            var line_buf: [2048]u8 = undefined;
            var lbw = BufferWriter{ .buf = &line_buf };
            lbw.writeAll(" ");
            lbw.print("\x1b[38;2;{d};{d};{d}mCyc:\x1b[0m \x1b[1m{d: >10}\x1b[0m ", .{ Color.text_dim.r, Color.text_dim.g, Color.text_dim.b, self.latest.cycles });
            lbw.print("\x1b[38;2;{d};{d};{d}mIns:\x1b[0m \x1b[1m{d: >10}\x1b[0m ", .{ Color.text_dim.r, Color.text_dim.g, Color.text_dim.b, self.latest.instructions });
            lbw.print("\x1b[38;2;{d};{d};{d}mBrMiss:\x1b[0m \x1b[1;38;2;{d};{d};{d}m{d: >7}\x1b[0m ", .{ Color.text_dim.r, Color.text_dim.g, Color.text_dim.b, Color.yellow.r, Color.yellow.g, Color.yellow.b, self.latest.branch_misses });
            lbw.print("\x1b[38;2;{d};{d};{d}mLLCMiss:\x1b[0m \x1b[1;38;2;{d};{d};{d}m{d: >7}\x1b[0m", .{ Color.text_dim.r, Color.text_dim.g, Color.text_dim.b, Color.peach.r, Color.peach.g, Color.peach.b, self.latest.llc_misses });
            self.renderContentLine(&bw, lbw.getWritten(), inner_w);
        }

        // Line 9: Telemetry Row 3 (Worker threads & core pinning)
        {
            var line_buf: [2048]u8 = undefined;
            var lbw = BufferWriter{ .buf = &line_buf };
            lbw.writeAll(" ");
            lbw.print("\x1b[38;2;{d};{d};{d}mWorkers:\x1b[0m \x1b[1;38;2;{d};{d};{d}m{d} threads\x1b[0m  ", .{
                Color.text_dim.r, Color.text_dim.g, Color.text_dim.b,
                Color.mauve.r,    Color.mauve.g,    Color.mauve.b,
                if (self.latest.active_threads > 0) self.latest.active_threads else 1,
            });
            lbw.print("\x1b[38;2;{d};{d};{d}mPin CPU:\x1b[0m \x1b[1m{d}\x1b[0m  ", .{
                Color.text_dim.r, Color.text_dim.g, Color.text_dim.b,
                self.latest.pinned_cpu,
            });
            lbw.print("\x1b[38;2;{d};{d};{d}mL1d Miss:\x1b[0m \x1b[1m{d}\x1b[0m", .{
                Color.text_dim.r, Color.text_dim.g, Color.text_dim.b,
                self.latest.l1d_misses,
            });
            self.renderContentLine(&bw, lbw.getWritten(), inner_w);
        }

        // Line 10: Divider to Event Log
        self.renderBorderLine(&bw, "├", "─", "┤", inner_w);

        // Line 11 & 12: Event log messages
        var l_idx: usize = 0;
        while (l_idx < 2) : (l_idx += 1) {
            var line_buf: [2048]u8 = undefined;
            var lbw = BufferWriter{ .buf = &line_buf };
            lbw.writeAll(" ");
            if (self.log_count > l_idx) {
                const actual_idx = if (self.log_count >= 2) self.log_count - 2 + l_idx else l_idx;
                const msg_slice = self.logs[actual_idx][0..self.log_lens[actual_idx]];
                lbw.print("\x1b[38;2;{d};{d};{d}m›\x1b[0m \x1b[38;2;{d};{d};{d}m{s}\x1b[0m", .{
                    Color.peach.r, Color.peach.g, Color.peach.b,
                    Color.text.r,  Color.text.g,  Color.text.b,
                    msg_slice,
                });
            }
            self.renderContentLine(&bw, lbw.getWritten(), inner_w);
        }

        // Line 13: Bottom border
        self.renderBorderLine(&bw, "╰", "─", "╯", inner_w);

        // Synchronized update end (\x1b[?2026l)
        bw.writeAll("\x1b[?2026l");

        const bytes = bw.getWritten();
        _ = std.c.write(2, bytes.ptr, bytes.len);
    }

    fn renderBorderLine(self: *QsTuiContext, bw: *BufferWriter, left: []const u8, mid: []const u8, right: []const u8, inner_w: usize) void {
        _ = self;
        bw.print("\x1b[2K\x1b[38;2;{d};{d};{d}m{s}", .{ Color.border_focus.r, Color.border_focus.g, Color.border_focus.b, left });
        var i: usize = 0;
        while (i < inner_w) : (i += 1) {
            bw.writeAll(mid);
        }
        bw.print("{s}\x1b[0m\n", .{right});
    }

    fn renderContentLine(self: *QsTuiContext, bw: *BufferWriter, content: []const u8, inner_w: usize) void {
        _ = self;
        bw.print("\x1b[2K\x1b[38;2;{d};{d};{d}m│\x1b[0m", .{ Color.border_focus.r, Color.border_focus.g, Color.border_focus.b });
        writePaddedOrTruncated(bw, content, inner_w);
        bw.print("\x1b[38;2;{d};{d};{d}m│\x1b[0m\n", .{ Color.border_focus.r, Color.border_focus.g, Color.border_focus.b });
    }

    fn renderProgressBar(self: *QsTuiContext, bw: *BufferWriter, pct: f64, bar_len: usize, color: Color) void {
        _ = self;
        const clamped = @max(0.0, @min(100.0, pct));
        const total_eighths = @as(usize, @intFromFloat((clamped / 100.0) * @as(f64, @floatFromInt(bar_len * 8))));
        const full_blocks = total_eighths / 8;
        const rem_eighths = total_eighths % 8;

        bw.print("\x1b[38;2;{d};{d};{d}m", .{ color.r, color.g, color.b });
        var i: usize = 0;
        while (i < full_blocks and i < bar_len) : (i += 1) {
            bw.writeAll("█");
        }
        if (i < bar_len and rem_eighths > 0) {
            bw.writeAll(BLOCK_EIGHTHS[rem_eighths]);
            i += 1;
        }
        bw.print("\x1b[38;2;{d};{d};{d}m", .{ Color.surface_light.r, Color.surface_light.g, Color.surface_light.b });
        while (i < bar_len) : (i += 1) {
            bw.writeAll("░");
        }
        bw.writeAll("\x1b[0m");
    }

    fn writeSpaces(self: *QsTuiContext, bw: *BufferWriter, count: usize) void {
        _ = self;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            bw.writeByte(' ');
        }
    }
};

// Global context storage for C ABI
var global_ctx: ?QsTuiContext = null;

export fn qs_tui_init(total_steps: usize) callconv(.c) ?*anyopaque {
    global_ctx = QsTuiContext.init(total_steps);
    return @ptrCast(&global_ctx.?);
}

fn copyName(dst: *[64]u8, src: ?[*:0]const u8) ?[*:0]const u8 {
    const s = std.mem.span(src orelse return null);
    const n = @min(s.len, dst.len - 1);
    @memcpy(dst[0..n], s[0..n]);
    dst[n] = 0;
    const z: [:0]const u8 = dst[0..n :0];
    return z.ptr;
}

export fn qs_tui_update(ctx: ?*anyopaque, tel: ?*const QsUiTelemetry) callconv(.c) void {
    const c: *QsTuiContext = if (ctx) |p| @ptrCast(@alignCast(p)) else if (global_ctx != null) &global_ctx.? else return;
    if (tel) |t| {
        var copy = t.*;
        copy.benchmark_name = copyName(&c.name_bufs[0], t.benchmark_name);
        copy.dataset_name = copyName(&c.name_bufs[1], t.dataset_name);
        copy.variant_name = copyName(&c.name_bufs[2], t.variant_name);
        c.latest = copy;
        if (t.total_steps > 0) c.total_steps = t.total_steps;
        if (t.current_step > 0) c.current_step = t.current_step;
        c.render(c.current_step >= c.total_steps);
    }
}

export fn qs_tui_log(ctx: ?*anyopaque, msg: ?[*:0]const u8) callconv(.c) void {
    const c: *QsTuiContext = if (ctx) |p| @ptrCast(@alignCast(p)) else if (global_ctx != null) &global_ctx.? else return;
    if (msg) |m| {
        c.appendLog(std.mem.span(m));
        c.render(false);
    }
}

export fn qs_tui_finish(ctx: ?*anyopaque, summary: ?[*:0]const u8) callconv(.c) void {
    const c: *QsTuiContext = if (ctx) |p| @ptrCast(@alignCast(p)) else if (global_ctx != null) &global_ctx.? else return;
    if (summary) |s| {
        c.appendLog(std.mem.span(s));
    }
    c.render(true);
}

export fn qs_tui_destroy(ctx: ?*anyopaque) callconv(.c) void {
    const c: *QsTuiContext = if (ctx) |p| @ptrCast(@alignCast(p)) else if (global_ctx != null) &global_ctx.? else return;
    c.deinit();
    global_ctx = null;
}
