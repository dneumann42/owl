const v = @import("values.zig");
const gc = @import("gc.zig");
const std = @import("std");
const e = @import("evaluation.zig");
const os = std.os;

const mibu = @import("mibu");
const events = mibu.events;
const term = mibu.term;
const utils = mibu.utils;
const cursor = mibu.cursor;
const clear = mibu.clear;

pub fn installBase(g: *gc.Gc) void {
    g.env().set("read-line", g.nfun(baseReadLine)) catch unreachable;
    g.env().set("echo", g.nfun(baseEcho)) catch unreachable;
    g.env().set("write", g.nfun(baseWrite)) catch unreachable;
    g.env().set("eval", g.nfun(baseEval)) catch unreachable;
}

pub fn errResult(g: *gc.Gc, msg: []const u8) *v.Value {
    std.log.err("{s}", .{msg});
    return g.nothing();
}

pub fn evalErrResult(g: *gc.Gc, err: e.EvalError) *v.Value {
    std.log.err("{any}", .{err});
    return errResult(g, "Evaluation error");
}

fn baseEcho(g: *gc.Gc, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        var it: ?*v.Value = arguments;
        while (it) |value| {
            const val = e.evaluate(g, value.cons.car.?) catch |err| return evalErrResult(g, err);
            const s = val.toString(g.allocator) catch return errResult(g, "Failed to allocate string");
            defer g.allocator.free(s);
            std.debug.print("{s} ", .{s});
            it = value.cons.cdr;
        }
        std.debug.print("\n", .{});
    }
    return g.T();
}

fn baseWrite(g: *gc.Gc, args: ?*v.Value) *v.Value {
    const stdout = std.io.getStdOut().writer();

    if (args) |arguments| {
        var it: ?*v.Value = arguments;
        while (it) |value| {
            const val = e.evaluate(g, value.cons.car.?) catch |err| return evalErrResult(g, err);
            const s = val.toString(g.allocator) catch return errResult(g, "Failed to allocate string");
            defer g.allocator.free(s);
            const buffer = convertEscapeSequences(g.allocator, s) catch unreachable;
            _ = stdout.print("{s}", .{buffer}) catch unreachable;
            it = value.cons.cdr;
        }
    }
    return g.T();
}

pub fn convertEscapeSequences(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (i + 3 < input.len and
            input[i] == '\\' and
            input[i + 1] == 'x' and
            input[i + 2] == '1' and
            input[i + 3] == 'b')
        {
            try result.append(0x1B);
            i += 4;
        } else if (i + 1 < input.len and input[i] == '\\' and input[i + 1] == 'n') {
            try result.append(0x0A);
            i += 2;
        } else if (i + 1 < input.len and input[i] == '\\' and input[i + 1] == 't') {
            try result.append(0x09);
            i += 2;
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

const ReadLine = struct {
    history: std.ArrayList([]const u8),
};

var readLine: ?ReadLine = null;

pub fn baseReadLine(g: *gc.Gc, args: ?*v.Value) *v.Value {
    // may want to switch to u21 strings

    if (readLine == null) {
        readLine = .{ .history = std.ArrayList([]const u8).init(g.allocator) };
    }

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    var raw_term = term.enableRawMode(stdin.handle, .blocking) catch return errResult(g, "Failed to enable raw mode");
    defer raw_term.disableRawMode() catch {};

    // To listen mouse events, we need to enable mouse tracking
    stdout.writer().print("{s}", .{utils.enable_mouse_tracking}) catch unreachable;
    defer stdout.writer().print("{s}", .{utils.disable_mouse_tracking}) catch {};

    if (args) |arguments| {
        if (arguments.cons.car) |prompt| {
            const value = e.evaluate(g, prompt) catch unreachable;
            stdout.writer().print("{s}", .{value.string}) catch unreachable;
        }
    }

    var line = std.ArrayList(u8).init(g.allocator);
    defer line.deinit();

    while (true) {
        const next = events.next(stdin) catch unreachable;

        switch (next) {
            .key => |k| switch (k) {
                .char => |ke| {
                    const u: u8 = @intCast(ke);
                    line.append(u) catch unreachable;
                    stdout.writer().print("{c}", .{u}) catch unreachable;
                },
                .ctrl => |c| switch (c) {
                    'c' => break,
                    else => {},
                },
                .enter => {
                    break;
                },
                .backspace => {
                    if (line.items.len > 0) {
                        _ = line.pop();
                        cursor.goLeft(stdout.writer(), 1) catch {};
                        clear.line_from_cursor(stdout.writer()) catch {};
                    }
                },
                .up => {
                    if (readLine.?.history.items.len > 0) {
                        const popped = readLine.?.history.pop();
                        line.clearRetainingCapacity();
                        for (popped) |c| {
                            line.append(c) catch unreachable;
                        }
                        stdout.writer().print("{s}", .{line.items}) catch unreachable;
                    }
                },
                else => {
                    std.debug.print("K: {s}", .{k});
                },
            },
            else => {},
        }
    }

    stdout.writer().print("\n", .{}) catch unreachable;
    const str = v.arrayListToString(g.allocator, line) catch unreachable;
    cursor.goLeft(stdout.writer(), str.len) catch unreachable;
    readLine.?.history.append(str) catch unreachable;

    return g.str(str);
}

fn baseEval(g: *gc.Gc, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        const value = e.evaluate(g, arguments.cons.car orelse g.nothing()) catch g.nothing();
        return e.eval(g, value.string) catch g.nothing();
    }
    return g.nothing();
}
