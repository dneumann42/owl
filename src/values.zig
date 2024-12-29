const std = @import("std");
const json = std.json;
const gc = @import("gc.zig");
const ValueError = error{KeyNotFound};

pub const ValueType = enum { nothing, number, string, symbol, boolean, cons, function, dictionary, nativeFunction };

pub const Cons = struct { car: ?*Value, cdr: ?*Value };

pub const NativeFunction = *const fn (*gc.Gc, std.ArrayList(*Value)) *Value;

pub const Value = union(ValueType) {
    nothing: void,
    number: f64,
    string: []const u8,
    symbol: []const u8, // TODO intern
    boolean: bool,
    cons: Cons,
    function: Function,
    dictionary: Dictionary,
    nativeFunction: NativeFunction,

    pub fn isStatic(self: *Value) bool {
        return self.dictionary.static;
    }

    pub fn isNothing(self: *Value) bool {
        return switch (self.*) {
            Value.nothing => true,
            else => false,
        };
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
                return std.fmt.allocPrint(allocator, "[fn:{d}]", .{f.address});
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

    pub fn toStr(self: *Value) []const u8 {
        return self.toString(std.heap.page_allocator) catch "";
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
            .function => |f| f.address == b.function.address,
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

pub fn arrayListToString(allocator: std.mem.Allocator, list: std.ArrayList(u8)) ![]u8 {
    const string = try allocator.alloc(u8, list.items.len);
    errdefer allocator.free(string);
    @memcpy(string, list.items);
    return string;
}

pub const Function = struct {
    address: usize,
    params: std.ArrayList([]const u8),
    env: *Environment,
    pub fn init(address: usize, params: std.ArrayList([]const u8), env: *Environment) Function {
        return Function{ .address = address, .params = params, .env = env };
    }
    pub fn deinit(self: *Function) void {
        self.params.deinit();
    }
};

pub const Dictionary = struct {
    pairs: *Value,
    g: *gc.Gc,
    static: bool,

    pub fn init(g: *gc.Gc) !@This() {
        return .{
            .pairs = try g.create(.{ .cons = .{ .car = null, .cdr = null } }),
            .g = g,
            .static = false,
        };
    }

    pub fn init_record(g: *gc.Gc, fields: std.ArrayList(*Value)) Dictionary {
        var xs = try g.create(.{ .cons = .{ .car = null, .cdr = null } });

        for (fields) |f| {
            xs = cons(g, cons(g, f, g.nothing()), xs);
        }

        return .{
            .pairs = xs,
            .g = g,
            .static = true,
        };
    }

    pub fn deinit(self: *Dictionary) void {
        // NOTE: this will be needed once we switch to a hash based dictionary
        _ = self;
    }

    pub fn get(self: Dictionary, key: *Value) ?*Value {
        var it: ?*Value = self.pairs;
        while (it != null) : (it = it.?.cons.cdr) {
            const pair = it.?.cons.car;
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
        if (self.static) {
            return error.KeyNotFound;
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
    allocator: std.mem.Allocator,
    next: ?*Environment,
    values: std.StringHashMap(*Value),

    pub fn init(allocator: std.mem.Allocator) !*Environment {
        const env = try allocator.create(Environment);
        env.* = .{ //
            .allocator = allocator,
            .next = null,
            .values = std.StringHashMap(*Value).init(allocator),
        };
        return env;
    }

    pub fn deinit(self: *Environment) void {
        if (self.next) |nextEnv| {
            nextEnv.deinit();
        }

        self.values.deinit();
        self.allocator.destroy(self);
    }

    pub fn find(self: *Environment, key: []const u8) ?*Value {
        if (self.values.get(key)) |v| {
            return v;
        }

        if (self.next) |next| {
            return next.find(key);
        }

        return null;
    }

    pub fn define(self: *Environment, key: []const u8, val: *Value) !void {
        try self.values.put(key, val);
    }

    pub fn set(self: *Environment, key: []const u8, val: *Value) !void {
        if (self.values.get(key) == null) {
            var it = self.next;
            while (it != null) : (it = it.?.next) {
                if (it.?.values.get(key) != null) {
                    try it.?.values.put(key, val);
                    return;
                }
            }
        }
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

pub fn nothing(g: *gc.Gc) *Value {
    const memo = struct {
        var value: ?*Value = null;
    };
    if (memo.value == null) {
        memo.value = g.create(Value.nothing) catch unreachable;
    }
    return memo.value orelse unreachable;
}
