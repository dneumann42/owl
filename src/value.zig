const std = @import("std");
const g = @import("gc.zig");

pub const Value = union(enum) { //
    nothing: void,
    number: f64,
    boolean: bool,
    symbol: []const u8,
    string: []const u8,
    list: std.ArrayList(usize),
    ffun: ForeignFunction,
    fun: Function,
};

pub const ForeignFunction = *const fn (*g.Gc, []usize) ?usize;

pub const ForeignFunctionBinding = struct {
    name: []const u8,
    ffun: ForeignFunction,
};

pub const Function = struct { env: *Environment, params: std.ArrayList([]const u8), body: usize };

pub const Environment = struct {
    allocator: std.mem.Allocator,

    next: ?*Environment,
    scope: Dictionary,

    pub fn init(allocator: std.mem.Allocator) !*Environment {
        const env = try allocator.create(Environment);
        env.* = .{ .allocator = allocator, .next = null, .scope = Dictionary.init(allocator) };
        return env;
    }

    pub fn deinit(self: *Environment) void {
        self.scope.clearAndFree();
        var it = self.next;
        while (it != null) : (it = it.?.next) {
            it.?.deinit();
        }
        self.allocator.destroy(self);
    }

    pub fn push(self: *Environment) !*Environment {
        const new_env = try Environment.init(self.allocator);
        new_env.next = self;
        return new_env;
    }

    pub fn find(self: Environment, key: usize) ?usize {
        if (self.scope.contains(key)) {
            return self.scope.get(key);
        }
        if (self.next) |next| {
            return next.find(key);
        }
        return null;
    }

    pub fn put(self: *Environment, key: usize, value: usize) !void {
        try self.scope.put(key, value);
    }
};

pub const ValueDictionary = std.HashMap(*Value, *Value, ValueKeyContext, std.hash_map.default_max_load_percentage);
pub const Dictionary = std.AutoHashMap(usize, usize);

pub fn toNumber(value: *const Value) f64 {
    return switch (value.*) {
        .number => |n| n,
        .boolean => |b| if (b) 1 else 0,
        else => 0,
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

pub fn isEql(self: ?*const Value, other: ?*const Value) bool {
    if (self == null) {
        return other == null;
    }

    const a = self.?;
    const b = other.?;

    return switch (a.*) {
        .nothing => true,
        .number => |n| n == b.number,
        .string => |s| std.mem.eql(u8, s, b.string),
        .symbol => |s| std.mem.eql(u8, s, b.symbol),
        .boolean => |bol| bol == b.boolean,
        .ffun => |f| f == b.ffun,
        .list, .fun => false, // TODO
    };
}

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
