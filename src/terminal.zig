// simple ansii terminal

const std = @import("std");

pub const Terminal = struct {
    // ANSI escape codes
    pub const RESET = "\x1b[0m";
    pub const BOLD = "\x1b[1m";
    pub const UNDERLINE = "\x1b[4m";

    // Colors
    pub const BLACK = "\x1b[30m";
    pub const RED = "\x1b[31m";
    pub const GREEN = "\x1b[32m";
    pub const YELLOW = "\x1b[33m";
    pub const BLUE = "\x1b[34m";
    pub const MAGENTA = "\x1b[35m";
    pub const CYAN = "\x1b[36m";
    pub const WHITE = "\x1b[37m";

    // Background colors
    pub const BG_BLACK = "\x1b[40m";
    pub const BG_RED = "\x1b[41m";
    pub const BG_GREEN = "\x1b[42m";
    pub const BG_YELLOW = "\x1b[43m";
    pub const BG_BLUE = "\x1b[44m";
    pub const BG_MAGENTA = "\x1b[45m";
    pub const BG_CYAN = "\x1b[46m";
    pub const BG_WHITE = "\x1b[47m";

    pub fn printColored(text: []const u8, color: []const u8, bg_color: ?[]const u8, bold: bool) void {
        var style: []const u8 = "";
        if (bold) style = BOLD;

        if (bg_color) |bg| {
            std.debug.print("{s}{s}{s}{s}{s}", .{ style, color, bg, text, RESET });
        } else {
            std.debug.print("{s}{s}{s}{s}", .{ style, color, text, RESET });
        }
    }

    pub fn inputColored(prompt: []const u8, color: []const u8) ![]const u8 {
        std.debug.print("{s}{s}{s}", .{ color, prompt, RESET });
        var buffer: [1024]u8 = undefined;
        const input = try std.io.getStdIn().reader().readUntilDelimiterOrEof(&buffer, '\n');
        return if (input) |line| line else "";
    }

    pub fn clear() void {
        std.debug.print("\x1b[2J\x1b[H", .{});
    }

    pub fn moveCursor(x: u32, y: u32) void {
        std.debug.print("\x1b[{};{}H", .{ y, x });
    }

    pub fn resetCursor() void {
        std.debug.print("\x1b[H", .{});
    }

    pub fn moveCursorUp(lines: u32) void {
        std.debug.print("\x1b[{}A", .{lines});
    }

    pub fn moveCursorDown(lines: u32) void {
        std.debug.print("\x1b[{}B", .{lines});
    }

    pub fn moveCursorRight(columns: u32) void {
        std.debug.print("\x1b[{}C", .{columns});
    }

    pub fn moveCursorLeft(columns: u32) void {
        std.debug.print("\x1b[{}D", .{columns});
    }

    pub fn saveCursorPosition() void {
        std.debug.print("\x1b[s", .{});
    }

    pub fn restoreCursorPosition() void {
        std.debug.print("\x1b[u", .{});
    }
};
