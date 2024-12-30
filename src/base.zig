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
    g.env().define("read-line", g.nfun(baseReadLine)) catch unreachable;
    g.env().define("echo", g.nfun(baseEcho)) catch unreachable;
    g.env().define("write", g.nfun(baseWrite)) catch unreachable;
    g.env().define("cat", g.nfun(concat)) catch unreachable;
    g.env().define("list-add", g.nfun(baseListAdd)) catch unreachable;
    g.env().define("list-remove", g.nfun(baseListAdd)) catch unreachable;
    g.env().define("dict-keys", g.nfun(baseDictKeys)) catch unreachable;
    g.env().define("ref", g.nfun(baseDictRef)) catch unreachable;
    g.env().define("nth", g.nfun(baseNth)) catch unreachable;
    g.env().define("len", g.nfun(baseLen)) catch unreachable;
}

pub fn errResult(g: *gc.Gc, msg: []const u8) *v.Value {
    std.log.err("{s}", .{msg});
    return g.nothing();
}

pub fn evalErrResult(g: *gc.Gc, err: e.EvalError) *v.Value {
    std.log.err("{any}", .{err});
    return errResult(g, "Evaluation error");
}

fn baseLen(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    const item = args.items[0];
    return switch (item.*) {
        .list => |xs| g.num(@floatFromInt(xs.items.len)),
        .string => |s| g.num(@floatFromInt(s.len)),
        .symbol => |s| g.num(@floatFromInt(s.len)),
        else => g.num(0.0),
    };
}

fn baseNth(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    const list = args.items[0];
    const index: usize = @intFromFloat(args.items[1].number);

    if (index >= list.list.items.len) {
        return g.nothing();
    }

    return list.list.items[index];
}

fn baseListRemove(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    _ = g;
    const list = args.items[0];
    list.list.swapRemove(@intFromFloat(args.items[1].number));
    return list;
}

fn baseDictKeys(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    const dict = args.items[0];
    var keys = std.ArrayList(*v.Value).init(g.allocator);
    var iterator = dict.dictionary.keyIterator();
    while (iterator.next()) |key| {
        keys.append(key.*) catch unreachable;
    }
    return v.clist(g, keys);
}

fn baseDictRef(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    const dict = args.items[0];
    const key = args.items[1];
    return dict.dictionary.get(key) orelse g.nothing();
}

fn baseListAdd(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    _ = g;
    const list = args.items[0];
    for (1..args.items.len) |i| {
        list.list.append(args.items[i]) catch unreachable;
    }
    return list;
}

fn baseEcho(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    const outw = std.io.getStdOut().writer();
    var i: usize = 0;
    while (i < args.items.len) : (i += 1) {
        const s = v.toStringRaw(args.items[i], g.allocator, true) catch return errResult(g, "Failed to allocate string");
        outw.print("{s}", .{s}) catch unreachable;
        if (i < args.items.len - 1) {
            _ = outw.write(" ") catch unreachable;
        }
    }
    _ = outw.write("\n") catch unreachable;
    return g.T();
}

fn baseWrite(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    const outw = std.io.getStdOut().writer();
    var i: usize = 0;
    while (i < args.items.len) : (i += 1) {
        const s = v.toStringRaw(args.items[i], g.allocator, false) catch return errResult(g, "Failed to allocate string");
        outw.print("{s}", .{s}) catch unreachable;
    }
    return g.T();
}

// TODO: all string literals should run through this function on read
const ReadLine = struct {
    history: std.ArrayList([]const u8),
};

var readLine: ?ReadLine = null;

pub fn baseReadLine(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
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

    if (args.items.len > 0) {
        const prompt = args.items[0];
        stdout.writer().print("{s}", .{prompt.string}) catch unreachable;
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
                    'l' => {
                        line.clearRetainingCapacity();
                        clear.screenToCursor(stdout.writer()) catch {};
                        cursor.goTo(stdout.writer(), 0, 0) catch unreachable;
                        if (args.items.len > 0) {
                            const prompt = args.items[0];
                            stdout.writer().print("{s}", .{prompt.string}) catch unreachable;
                        }
                    },
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
    cursor.goLeft(stdout.writer(), str.len + 2) catch unreachable;
    readLine.?.history.append(str) catch unreachable;

    return g.str(str);
}

fn concat(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    var strs = std.ArrayList([]const u8).init(g.allocator);
    for (args.items) |arg| {
        strs.append(v.toStringRaw(arg, g.allocator, false) catch unreachable) catch unreachable;
    }
    return g.str(std.mem.join(g.allocator, "", strs.items) catch unreachable);
}
