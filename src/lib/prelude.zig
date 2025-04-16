const std = @import("std");
const v = @import("../value.zig");
const g = @import("../gc.zig");
const Gc = g.Gc;
const Value = v.Value;

pub fn toString(value: *const Value, gc: *Gc, allocator: std.mem.Allocator) ![]const u8 {
    return switch (value.*) {
        .nothing => std.fmt.allocPrint(allocator, "Nothing", .{}),
        .boolean => |b| std.fmt.allocPrint(allocator, "{s}", .{if (b) "#t" else "#f"}),
        .number => |n| std.fmt.allocPrint(allocator, "{d}", .{n}),
        .string => |s| std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .symbol => |s| std.fmt.allocPrint(allocator, "{s}", .{s}),
        .ffun => std.fmt.allocPrint(allocator, "<ffun>", .{}),
        .fun => std.fmt.allocPrint(allocator, "<fun>", .{}),
        .list => |xs| {
            var strs = std.ArrayList([]const u8).init(allocator);
            defer strs.deinit();
            try strs.append("(");

            for (xs.items) |item| {
                const str = try toString(gc.getValue(item), gc, allocator);
                try strs.append(str);
            }

            try strs.append(")");
            return std.mem.join(allocator, " ", strs.items);
        },
    };
}

fn add(gc: *Gc, args: []usize) ?usize {
    var total: f64 = 0.0;
    for (args) |arg| total += v.toNumber(gc.getValue(arg));
    return gc.number(total);
}

fn mul(gc: *Gc, args: []usize) ?usize {
    var total: f64 = 1.0;
    for (args) |arg| total *= v.toNumber(gc.getValue(arg));
    return gc.number(total);
}

fn sub(gc: *Gc, args: []usize) ?usize {
    var total: f64 = v.toNumber(gc.getValue(args[0]));
    for (1..args.len) |i| total -= v.toNumber(gc.getValue(args[i]));
    return gc.number(total);
}

fn div(gc: *Gc, args: []usize) ?usize {
    var total: f64 = v.toNumber(gc.getValue(args[0]));
    for (1..args.len) |i| total /= v.toNumber(gc.getValue(args[i]));
    return gc.number(total);
}

fn echo(gc: *Gc, args: []usize) ?usize {
    var arena = std.heap.ArenaAllocator.init(gc.allocator);
    defer arena.deinit();

    const stdout = std.io.getStdOut().writer();
    for (0..args.len) |i| {
        const str = toString(gc.getValue(args[i]), gc, arena.allocator()) catch unreachable;
        stdout.print("{s}", .{str}) catch unreachable;
        if (i < args.len - 1) {
            stdout.print(" ", .{}) catch unreachable;
        }
    }
    stdout.print("\n", .{}) catch unreachable;
    return null;
}

pub fn prelude() []const v.ForeignFunctionBinding {
    return comptime &[_]v.ForeignFunctionBinding{
        .{ .name = "+", .ffun = add },
        .{ .name = "-", .ffun = sub },
        .{ .name = "*", .ffun = mul },
        .{ .name = "/", .ffun = div },
        .{ .name = "echo", .ffun = echo },
    };
}
