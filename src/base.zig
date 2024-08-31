const v = @import("values.zig");
const gc = @import("gc.zig");
const std = @import("std");
const e = @import("evaluation.zig");

pub fn installBase(g: *gc.Gc) void {
    g.env().set("read-line", g.nfun(baseReadLine)) catch unreachable;
    g.env().set("echo", g.nfun(baseEcho)) catch unreachable;
    g.env().set("write", g.nfun(baseWrite)) catch unreachable;
    g.env().set("eval", g.nfun(baseEval)) catch unreachable;
}

fn baseEcho(g: *gc.Gc, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        var it: ?*v.Value = arguments;
        while (it) |value| {
            const val = e.evaluate(g, value.cons.car.?) catch unreachable;
            const s = val.toString(g.allocator) catch unreachable;
            defer g.allocator.free(s);
            std.debug.print("{s} ", .{s});
            it = value.cons.cdr;
        }
        std.debug.print("\n", .{});
    }
    return g.T();
}

fn baseWrite(g: *gc.Gc, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        var it: ?*v.Value = arguments;
        while (it) |value| {
            const val = e.evaluate(g, value.cons.car.?) catch unreachable;
            const s = val.toString(g.allocator) catch unreachable;
            defer g.allocator.free(s);
            std.debug.print("{s}", .{s});
            it = value.cons.cdr;
        }
        std.debug.print("\n", .{});
    }
    return g.T();
}

pub fn baseReadLine(g: *gc.Gc, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        if (arguments.cons.car) |prompt| {
            const stdout = std.io.getStdOut().writer();
            const value = e.evaluate(g, prompt) catch unreachable;
            stdout.print("{s}", .{value.string}) catch unreachable;
        }
    }
    const stdin = std.io.getStdIn().reader();
    const line = stdin.readUntilDelimiterAlloc(g.allocator, '\n', 1024 * 8) catch unreachable;
    return g.str(line);
}

fn baseEval(g: *gc.Gc, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        const value = e.evaluate(g, arguments.cons.car orelse g.nothing()) catch g.nothing();
        return e.eval(g, value.string) catch g.nothing();
    }
    return g.nothing();
}
