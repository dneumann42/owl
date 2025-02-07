const std = @import("std");
const json = std.json;
const gc = @import("gc.zig");
const ValueError = error{KeyNotFound};

pub const ValueType = enum {
    nothing, //
    number,
    string,
    symbol,
    boolean,
    cons,
    list,
    module,
    function,
    dictionary,
    nativeFunction,
};

pub const Value = union(ValueType) {
    nothing: void,
    number: f64,
    string: []const u8,
    symbol: []const u8, // TODO intern
    boolean: bool,
    cons: Cons,
    list: List,
    module: Module,
    function: Function,
    dictionary: Dictionary,
    nativeFunction: NativeFunction,
};

pub const Module = struct {
    name: []const u8,
    value: *Value,
};

pub fn isNothing(self: *Value) bool {
    return switch (self.*) {
        .nothing => true,
        else => false,
    };
}

pub fn toStringRaw(self: *Value, allocator: std.mem.Allocator, literal: bool, short: bool) ![]const u8 {
    switch (self.*) {
        .nothing => {
            return std.fmt.allocPrint(allocator, "Nothing", .{});
        },
        .symbol => {
            return std.fmt.allocPrint(allocator, "{s}", .{self.symbol});
        },
        .string => |s| {
            if (literal) {
                return std.fmt.allocPrint(allocator, "\"{s}\"", .{s});
            } else {
                return std.fmt.allocPrint(allocator, "{s}", .{s});
            }
        },
        .number => {
            return std.fmt.allocPrint(allocator, "{d}", .{self.number});
        },
        .boolean => |b| {
            const s = if (b) "true" else "false";
            return std.fmt.allocPrint(allocator, "{s}", .{s});
        },
        .module => |m| {
            return std.fmt.allocPrint(allocator, "<module: {s}>", .{m.name});
        },
        .function => |f| {
            return std.fmt.allocPrint(allocator, "<fn {d}>", .{f.address});
        },
        .nativeFunction => {
            return std.fmt.allocPrint(allocator, "<native>", .{});
        },
        .cons => {
            if (short) {
                return std.fmt.allocPrint(allocator, "( .. )", .{});
            }
            var it: ?*Value = self;
            var strings = std.ArrayList([]const u8).init(allocator);

            while (it != null) : (it = it.?.cons.cdr) {
                const cr = it.?.cons.car;
                if (cr) |value| {
                    try strings.append(try toStringRaw(value, allocator, literal, short));

                    if (it.?.cons.cdr == null) {
                        break;
                    }

                    switch (it.?.cons.cdr.?.*) {
                        .cons => {},
                        else => {
                            try strings.append(" . ");
                            try strings.append(try toStringRaw(it.?.cons.cdr.?, allocator, literal, short));
                            break;
                        },
                    }
                }
            }

            const finalStr = try joinWithSpaces(allocator, strings);
            return std.fmt.allocPrint(allocator, "({s})", .{finalStr});
        },
        .list => |xs| {
            if (short) {
                return std.fmt.allocPrint(allocator, "[ .. ]", .{});
            }
            var strings = std.ArrayList([]const u8).init(allocator);
            for (xs.items) |item| {
                const str = try toStringRaw(item, allocator, literal, short);
                try strings.append(str);
            }
            const list_string = try std.mem.join(allocator, ", ", strings.items);
            return std.fmt.allocPrint(allocator, "[{s}]", .{list_string});
        },
        .dictionary => |dict| {
            if (short) {
                return std.fmt.allocPrint(allocator, "{{ .. }}", .{});
            }
            var strings = std.ArrayList([]const u8).init(allocator);
            var key_iterator = dict.keyIterator();
            while (key_iterator.next()) |key| {
                const value = dict.get(key.*) orelse continue;
                const s = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ try toString(key.*, allocator), try toStringRaw(value, allocator, literal, short) });
                try strings.append(s);
            }

            const list_string = try std.mem.join(allocator, ", ", strings.items);
            return std.fmt.allocPrint(allocator, "{{ {s} }}", .{list_string});
        },
    }
}

pub fn toString(self: *Value, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    return toStringRaw(self, allocator, true, false);
}

pub fn toStringShort(self: *Value, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    return toStringRaw(self, allocator, true, true);
}

pub fn toStr(self: *Value) []const u8 {
    return toString(self, std.heap.page_allocator) catch "";
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
        .module => |m| std.mem.eql(u8, m.name, b.module.name),
        .boolean => |bol| bol == b.boolean,
        .cons => (isEql(a.cons.car, b.cons.car) and isEql(a.cons.cdr, b.cons.cdr)),
        .function => |f| f.address == b.function.address,
        .dictionary => false, // TODO
        .list => false, // TODO
        .nativeFunction => a.nativeFunction == b.nativeFunction,
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
    return !isTrue(self);
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

pub const Cons = struct { car: ?*Value, cdr: ?*Value };
pub const List = std.ArrayList(*Value);

pub const NativeFunction = *const fn (*gc.Gc, std.ArrayList(*Value)) *Value;

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
    pub fn deinit(self: Function) void {
        self.params.deinit();
    }
};

const ValueKeyContext = struct {
    pub fn hash(ctx: ValueKeyContext, key: *Value) u64 {
        _ = ctx;
        var h = std.hash.Fnv1a_64.init();

        switch (key.*) {
            .string => |s| {
                h.update(s);
            },
            .symbol => |s| {
                h.update(s);
            },
            .number => |n| {
                const i: u64 = @intFromFloat(n);
                var bytes: [8]u8 = undefined;
                std.mem.writeInt(u64, bytes[0..], i, std.builtin.Endian.little);
                h.update(bytes[0..]);
            },
            .boolean => |b| {
                const i = @intFromBool(b);
                const bytes = [_]u8{@intCast(i)};
                h.update(bytes[0..]);
            },
            else => {
                @panic("Invalid dictionary key value");
            },
        }
        return h.final();
    }

    pub fn eql(ctx: ValueKeyContext, a: *Value, b: *Value) bool {
        _ = ctx;
        return isEql(a, b);
    }
};

pub const Dictionary = std.HashMap(*Value, *Value, ValueKeyContext, std.hash_map.default_max_load_percentage);

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
        self.values.deinit();
        self.allocator.destroy(self);
    }

    pub fn push(self: *Environment) *Environment {
        const new_env = Environment.init(self.allocator) catch unreachable;
        new_env.next = self;
        return new_env;
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
        } else {
            try self.values.put(key, val);
            return;
        }

        // throw an error if value doesn't exist in environment
        return error.KeyNotFound;
    }

    pub fn toString(self: *Environment, allocator: std.mem.Allocator) ![]const u8 {
        var lines = std.ArrayList([]const u8).init(allocator);
        defer lines.deinit();

        var env: ?*Environment = self;
        var index: i32 = 0;

        while (env) |e| {
            try lines.append(try std.fmt.allocPrint(allocator, "ENV #{d} count: {d}", .{ index, e.values.count() }));
            var iter = e.values.keyIterator();
            var xs = std.ArrayList([]const u8).init(allocator);
            defer xs.deinit();
            while (iter.next()) |it| {
                try xs.append(try std.fmt.allocPrint(allocator, "{s}", .{it.*}));
            }
            try lines.append(try std.mem.join(allocator, " ", xs.items));
            index += 1;
            env = env.?.next;
        }

        return std.mem.join(allocator, "\n", lines.items);
    }
};

pub fn clist(g: *gc.Gc, xs: std.ArrayList(*Value)) *Value {
    return g.create(.{ .list = xs }) catch |err| {
        std.debug.panic("Panicked at Error: {any}", .{err});
    };
}

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
