const v = @import("values.zig");
const gc = @import("gc.zig");
const std = @import("std");
const e = @import("evaluation.zig");
const os = std.os;

pub fn installBase(g: *gc.Gc, env: *v.Environment) void {
    env.define("echo", g.nfun(baseEcho)) catch unreachable;
    env.define("write", g.nfun(baseWrite)) catch unreachable;
    env.define("cat", g.nfun(concat)) catch unreachable;
    env.define("list-add", g.nfun(baseListAdd)) catch unreachable;
    env.define("list-remove", g.nfun(baseListAdd)) catch unreachable;
    env.define("dict-keys", g.nfun(baseDictKeys)) catch unreachable;
    env.define("ref", g.nfun(baseDictRef)) catch unreachable;
    env.define("nth", g.nfun(baseNth)) catch unreachable;
    env.define("len", g.nfun(baseLen)) catch unreachable;
    env.define("read-line", g.nfun(readLine)) catch unreachable;
}

pub fn errResult(g: *gc.Gc, msg: []const u8) *v.Value {
    std.log.err("{s}", .{msg});
    return g.nothing();
}

pub fn evalErrResult(g: *gc.Gc, err: e.EvalError) *v.Value {
    std.log.err("{any}", .{err});
    return errResult(g, "Evaluation error");
}

fn readLine(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    _ = args;
    var input: [1024]u8 = undefined;
    const outr = std.io.getStdOut().reader();
    const size = outr.readUntilDelimiter(&input, '\n') catch unreachable;
    return g.strAlloc(input[0..size.len]);
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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const outw = std.io.getStdOut().writer();
    var i: usize = 0;
    while (i < args.items.len) : (i += 1) {
        const s = v.toStringRaw(args.items[i], allocator, true, false) catch return errResult(g, "Failed to allocate string");
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
        const s = v.toStringRaw(args.items[i], g.allocator, false, false) catch return errResult(g, "Failed to allocate string");
        defer g.allocator.free(s);
        outw.print("{s}", .{s}) catch unreachable;
    }
    return g.T();
}

fn concat(g: *gc.Gc, args: std.ArrayList(*v.Value)) *v.Value {
    var strs = std.ArrayList([]const u8).init(g.allocator);
    for (args.items) |arg| {
        strs.append(v.toStringRaw(arg, g.allocator, false, false) catch unreachable) catch unreachable;
    }
    return g.str(std.mem.join(g.allocator, "", strs.items) catch unreachable);
}
