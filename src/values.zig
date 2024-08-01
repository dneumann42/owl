const std = @import("std");
const json = std.json;
const gc = @import("gc.zig");
const e = @import("evaluation.zig");

pub const ValueType = enum { nothing, number, string, symbol, boolean, cons, function, dictionary, nativeFunction };

pub const Cons = struct { car: ?*Value, cdr: ?*Value };

pub const Value = union(ValueType) {
    nothing: void,
    number: f64,
    string: []const u8,
    symbol: []const u8, // TODO intern
    boolean: bool,
    cons: Cons,
    function: Function,
    // NOTE: symbol values may not be the same pointer
    dictionary: std.AutoHashMap(*Value, Value),
    nativeFunction: *const fn (*Environment, ?*Value) *Value,

    pub fn num(g: *gc.Gc, n: f64) !*Value {
        return g.create(.{ .number = n });
    }

    pub fn sym(g: *gc.Gc, s: []const u8) !*Value {
        return g.create(.{ .symbol = s });
    }

    pub fn nfun(g: *gc.Gc, f: *const fn (*Environment, ?*Value) *Value) !*Value {
        return g.create(.{ .nativeFunction = f });
    }

    pub fn True(g: *gc.Gc) !*Value {
        return g.create(.{ .boolean = true });
    }

    pub fn False(g: *gc.Gc) !*Value {
        return g.create(.{ .boolean = false });
    }

    pub fn toString(self: *Value, allocator: std.mem.Allocator) ![]const u8 {
        switch (self.*) {
            Value.nothing => {
                return std.fmt.allocPrint(allocator, "Nothing", .{});
            },
            Value.symbol => {
                return std.fmt.allocPrint(allocator, "{s}", .{self.symbol});
            },
            Value.number => {
                return std.fmt.allocPrint(allocator, "{d}", .{self.number});
            },
            Value.boolean => |b| {
                const s = if (b) "true" else "false";
                return std.fmt.allocPrint(allocator, "{s}", .{s});
            },
            Value.function => |f| {
                const n = f.name.?.symbol;
                return std.fmt.allocPrint(allocator, "[fn: {s}]", .{n});
            },
            Value.nativeFunction => {
                return std.fmt.allocPrint(allocator, "[native-fn]", .{});
            },
            Value.cons => {
                var it: ?*Value = self;
                var strings = std.ArrayList([]const u8).init(allocator);
                while (it != null) {
                    if (it) |xs| {
                        if (xs.cons.car) |val| {
                            try strings.append(try val.toString(allocator));
                        }
                        it = xs.cons.cdr;
                    }
                }
                const finalStr = try joinWithSpaces(allocator, strings);
                return std.fmt.allocPrint(allocator, "({s})", .{finalStr});
            },
            else => {
                return std.fmt.allocPrint(allocator, "{any}", .{self.*});
            },
        }
    }

    fn getFormatString(value: *Value) []const u8 {
        return switch (value.*) {
            Value.nothing => "Nothing",
            Value.symbol => "{s}",
            Value.number => "{d}",
            Value.boolean => "{s}",
            Value.function => "[fn: {s}]",
            Value.nativeFunction => "[native-fn]",
            Value.cons => "({s})",
            else => "{any}",
        };
    }

    pub fn isBoolean(self: *const Value) bool {
        return switch (self.*) {
            .boolean => true,
            else => false,
        };
    }

    pub fn isTrue(self: *const Value) bool {
        return switch (self.*) {
            .boolean => |t| t != false,
            else => true,
        };
    }

    pub fn isFalse(self: *const Value) bool {
        return !self.isTrue();
    }

    pub fn toNumber(self: *const Value) f64 {
        return switch (self.*) {
            .number => self.number,
            else => 0.0,
        };
    }

    pub fn reverse(self: *Value) *Value {
        var prev: ?*Value = null;
        var current: ?*Value = self;
        while (current) |value| {
            const next = value.cons.cdr;
            value.cons.cdr = prev;
            prev = value;
            current = next;
        }
        if (prev) |value| {
            return value;
        }
        return self;
    }
};

pub fn joinWithSpaces(allocator: std.mem.Allocator, list: std.ArrayList([]const u8)) ![]u8 {
    return std.mem.join(allocator, " ", list.items);
}

pub const Function = struct {
    name: ?*Value,
    body: *Value,
    params: *Value,
};

fn preludeEcho(env: *Environment, args0: ?*Value) *Value {
    if (args0) |args| {
        var it: ?*Value = args;
        while (it != null) {
            if (it) |value| {
                const val = e.evaluate(env, value.cons.car.?) catch unreachable;
                const s = val.toString(env.gc.listAllocator) catch unreachable;
                defer env.gc.listAllocator.free(s);
                std.debug.print("{s} ", .{s});
                it = value.cons.cdr;
            }
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("\n", .{});
    return Value.True(env.gc) catch unreachable;
}

// Environment does not own the values and will not free them
pub const Environment = struct {
    gc: *gc.Gc,
    next: ?*Environment,
    values: std.StringHashMap(*Value),

    pub fn init(g: *gc.Gc) !*Environment {
        const env = try g.listAllocator.create(Environment);
        env.* = .{ .gc = g, .next = null, .values = std.StringHashMap(*Value).init(g.listAllocator) };

        try env.set("echo", try Value.nfun(g, preludeEcho));

        return env;
    }

    pub fn deinit(self: *Environment) void {
        self.values.deinit();
        self.gc.listAllocator.destroy(self);
    }

    pub fn push(self: *Environment) !*Environment {
        var new_environment = try Environment.init(self.gc);
        new_environment.next = self;
        return new_environment;
    }

    pub fn find(self: *Environment, key: []const u8) ?*Value {
        if (self.values.get(key)) |v| {
            return v;
        }

        if (self.next != null) {
            return self.next.?.find(key);
        }

        return null;
    }

    pub fn set(self: *Environment, key: []const u8, val: *Value) !void {
        try self.values.put(key, val);
    }
};

pub fn cons(g: *gc.Gc, vcar: ?*Value, vcdr: ?*Value) *Value {
    return g.create(.{ .cons = .{ .car = vcar, .cdr = vcdr } }) catch |err| {
        std.debug.panic("Panicked at Error: {any}", .{err});
    };
}

pub fn car(v: ?*Value) ?*Value {
    const val = v orelse return null;
    return switch (val.*) {
        .cons => val.cons.car,
        else => null,
    };
}

pub fn cdr(v: ?*Value) ?*Value {
    const val = v orelse return null;
    return switch (val.*) {
        .cons => val.cons.cdr,
        else => null,
    };
}

pub fn repr(val: *Value) void {
    _ = val;
}
