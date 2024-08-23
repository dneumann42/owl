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
    dictionary: Dictionary,
    nativeFunction: *const fn (*Environment, ?*Value) *Value,

    pub fn num(g: *gc.Gc, n: f64) !*Value {
        return g.create(.{ .number = n });
    }

    pub fn sym(g: *gc.Gc, s: []const u8) !*Value {
        return g.create(.{ .symbol = s });
    }

    pub fn str(g: *gc.Gc, s: []const u8) !*Value {
        return g.create(.{ .string = s });
    }

    pub fn nativeFun(g: *gc.Gc, f: *const fn (*Environment, ?*Value) *Value) !*Value {
        return g.create(.{ .nativeFunction = f });
    }

    pub fn boole(g: *gc.Gc, b: bool) !*Value {
        if (b) {
            return Value.owlTrue(g);
        }
        return Value.owlFalse(g);
    }

    pub fn owlTrue(g: *gc.Gc) !*Value {
        return g.create(.{ .boolean = true });
    }

    pub fn owlFalse(g: *gc.Gc) !*Value {
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
            Value.string => |s| {
                return std.fmt.allocPrint(allocator, "{s}", .{s});
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

                while (it != null) : (it = it.?.cons.cdr) {
                    const cr = it.?.cons.car;
                    if (cr) |value| {
                        try strings.append(try value.toString(allocator));

                        if (it.?.cons.cdr == null) {
                            break;
                        }

                        switch (it.?.cons.cdr.?.*) {
                            .cons => {},
                            else => {
                                try strings.append(" . ");
                                try strings.append(try it.?.cons.cdr.?.toString(allocator));
                                break;
                            },
                        }
                    }
                }

                const finalStr = try joinWithSpaces(allocator, strings);
                return std.fmt.allocPrint(allocator, "({s})", .{finalStr});
            },
            Value.dictionary => |dict| {
                var it: ?*Value = dict.pairs;
                var strings = std.ArrayList([]const u8).init(allocator);

                while (it != null) {
                    if (it) |xs| {
                        if (xs.cons.car) |pair| {
                            try strings.append(try pair.toString(allocator));
                        }
                        it = xs.cons.cdr;
                    }
                }

                const finalStr = try joinWithSpaces(allocator, strings);
                return std.fmt.allocPrint(allocator, "({s})", .{finalStr});
            },
        }
    }

    pub fn isEql(self: ?*const Value, other: ?*const Value) bool {
        if (self == null) {
            return other == null;
        }

        const a = self.?;
        const b = other.?;

        if (@as(ValueType, a.*) != @as(ValueType, b.*)) {
            return false;
        }

        return switch (a.*) {
            .nothing => true,
            .number => |n| n == b.number,
            .string => |s| std.mem.eql(u8, s, b.string),
            .symbol => |s| std.mem.eql(u8, s, b.symbol),
            .boolean => |bol| bol == b.boolean,
            .cons => (isEql(a.cons.car, b.cons.car) and isEql(a.cons.cdr, b.cons.cdr)),
            .function => |f| f.name == b.function.name and f.body == b.function.body and f.params == b.function.params,
            .dictionary => false, // TODO
            .nativeFunction => a.nativeFunction == b.nativeFunction,
        };
    }

    fn getFormatString(value: *Value) []const u8 {
        return switch (value.*) {
            .nothing => "Nothing",
            .symbol => "{s}",
            .number => "{d}",
            .boolean => "{s}",
            .function => "[fn: {s}]",
            .nativeFunction => "[native-fn]",
            .cons => "({s})",
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

pub fn getValueEqlFn(comptime K: type, comptime Context: type) (fn (Context, K, K) bool) {
    return struct {
        fn eql(ctx: Context, a: K, b: K) bool {
            _ = ctx;
            return a.isEql(b);
        }
    };
}

pub fn hashValue(value: *const Value, hasher: *std.hash.Wyhash) void {
    switch (value.*) {
        .string, .symbol => |s| std.hash.autoHashStrat(hasher, s, .Deep),
        .cons => |c| {
            if (c.car) |cr| {
                hashValue(cr, hasher);
            }
            if (c.cdr) |cd| {
                hashValue(cd, hasher);
            }
        },
        else => {},
    }
}

pub fn ValueContext(comptime K: type) type {
    return struct {
        pub fn hash(self: @This(), key: K) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hashValue(key, &hasher);
            return hasher.final();
        }

        pub fn eql(self: @This(), a: K, b: K) bool {
            _ = self;
            return std.meta.eql(a.*, b.*);
        }
    };
}

pub fn joinWithSpaces(allocator: std.mem.Allocator, list: std.ArrayList([]const u8)) ![]u8 {
    return std.mem.join(allocator, " ", list.items);
}

pub const Function = struct {
    name: ?*Value,
    body: *Value,
    params: *Value,
};

pub const Dictionary = struct {
    pairs: *Value,
    g: *gc.Gc,

    pub fn init(g: *gc.Gc) !@This() {
        return .{
            .pairs = try g.create(.{ .cons = .{ .car = null, .cdr = null } }),
            .g = g,
        };
    }

    pub fn deinit(self: *Dictionary) void {
        // NOTE: this will be needed once we switch to a hash based dictionary
        _ = self;
    }

    pub fn get(self: *Dictionary, key: *Value) ?Value {
        var it: ?*Value = self.pairs;
        while (it != null) : (it = it.?.cons.cdr) {
            const pair = it.?.car;
            if (pair) |p| {
                if (p.cons.car) |cr| {
                    if (cr.isEql(key)) {
                        return p.cons.cdr;
                    }
                }
            }
        }
        return null;
    }

    pub fn hasKey(self: *Dictionary, key: *Value) bool {
        var it: ?*Value = self.pairs;
        while (it) : (it = it.?.cons.cdr) {
            const pair = it.?.car;
            if (pair) |p| {
                if (p.cons.car) |cr| {
                    if (cr.isEql(key)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    pub fn putOrReplace(self: *Dictionary, key: *Value, value: *Value) !void {
        var it: ?*Value = self.pairs;
        while (it != null) : (it = it.?.cons.cdr) {
            const pair = it.?.cons.car;
            if (pair) |p| {
                if (p.cons.car) |cr| {
                    if (cr.isEql(key)) {
                        p.cons.cdr = value;
                        return;
                    }
                }
            }
        }
        self.pairs = cons(self.g, cons(self.g, key, value), self.pairs);
        return;
    }

    pub fn put(self: *Dictionary, key: *Value, value: *Value) !void {
        try self.putOrReplace(key, value);
    }
};

// Environment does not own the values and will not free them
pub const Environment = struct {
    gc: *gc.Gc,
    next: ?*Environment,
    values: std.StringHashMap(*Value),

    pub fn init(g: *gc.Gc) !*Environment {
        const env = try g.listAllocator.create(Environment);
        env.* = .{ .gc = g, .next = null, .values = std.StringHashMap(*Value).init(g.listAllocator) };
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
