const v = @import("values.zig");
const gc = @import("gc.zig");
const std = @import("std");
const e = @import("evaluation.zig");

pub fn installBase(env: *v.Environment, g: *gc.Gc) void {
    env.set("read-line", v.Value.nativeFun(g, baseReadLine) catch unreachable) catch unreachable;
    env.set("echo", v.Value.nativeFun(g, baseEcho) catch unreachable) catch unreachable;
    env.set("write", v.Value.nativeFun(g, baseWrite) catch unreachable) catch unreachable;
    env.set("eval", v.Value.nativeFun(g, baseEval) catch unreachable) catch unreachable;
}

fn baseEcho(env: *v.Environment, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        var it: ?*v.Value = arguments;
        while (it) |value| {
            const val = e.evaluate(env, value.cons.car.?) catch unreachable;
            const s = val.toString(env.gc.listAllocator) catch unreachable;
            defer env.gc.listAllocator.free(s);
            std.debug.print("{s} ", .{s});
            it = value.cons.cdr;
        }
        std.debug.print("\n", .{});
    }
    return v.Value.owlTrue(env.gc) catch unreachable;
}

fn baseWrite(env: *v.Environment, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        var it: ?*v.Value = arguments;
        while (it) |value| {
            const val = e.evaluate(env, value.cons.car.?) catch unreachable;
            const s = val.toString(env.gc.listAllocator) catch unreachable;
            defer env.gc.listAllocator.free(s);
            std.debug.print("{s}", .{s});
            it = value.cons.cdr;
        }
        std.debug.print("\n", .{});
    }
    return v.Value.owlTrue(env.gc) catch unreachable;
}

pub fn baseReadLine(env: *v.Environment, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        if (arguments.cons.car) |prompt| {
            const stdout = std.io.getStdOut().writer();
            const value = e.evaluate(env, prompt) catch unreachable;
            stdout.print("{s}", .{value.string}) catch unreachable;
        }
    }
    const stdin = std.io.getStdIn().reader();
    const line = stdin.readUntilDelimiterAlloc(env.gc.listAllocator, '\n', 1024 * 8) catch unreachable;
    return v.Value.str(env.gc, line) catch unreachable;
}

fn baseEval(env: *v.Environment, args: ?*v.Value) *v.Value {
    if (args) |arguments| {
        const value = e.evaluate(env, arguments.cons.car orelse e.nothing(env)) catch e.nothing(env);
        return e.eval(env, value.string) catch e.nothing(env);
    }
    return e.nothing(env);
}
