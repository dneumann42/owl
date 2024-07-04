const std = @import("std");
const json = std.json;

pub const ValueType = enum { nothing, number, string, symbol, boolean, cons };

pub const Cons = struct { car: ?*Value, cdr: ?*Value };

pub const Value = union(ValueType) {
    nothing: void,
    number: f64,
    string: []const u8,
    symbol: []const u8, // TODO intern
    boolean: bool,
    cons: Cons,

    pub fn num(allocator: std.mem.Allocator, n: f64) !*Value {
        const v = try allocator.create(Value);
        v.* = .{ .number = n };
        return v;
    }

    pub fn sym(allocator: std.mem.Allocator, s: []const u8) !*Value {
        const v = try allocator.create(Value);
        v.* = .{ .symbol = s };
        return v;
    }

    pub fn True(allocator: std.mem.Allocator) *Value {
        const v = allocator.create(Value);
        v.* = .{ .boolean = true };
        return v;
    }

    pub fn False(allocator: std.mem.Allocator) *Value {
        const v = allocator.create(Value);
        v.* = .{ .boolean = false };
        return v;
    }

    pub fn is_boolean(self: *const Value) bool {
        return switch (self.*) {
            .boolean => true,
            else => false,
        };
    }

    pub fn is_true(self: *const Value) bool {
        return switch (self.*) {
            .boolean => |t| t != false,
            else => true,
        };
    }

    pub fn is_false(self: *const Value) bool {
        return !self.is_true();
    }

    pub fn stringify(allocator: std.mem.Allocator, self: *const Value) ![]const u8 {
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();
        try json.stringify(self, .{ .whitespace = .indent_2 }, string.writer());
        return string.toOwnedSlice();
    }
};

// Environment does not own the values and will not free them
pub const Environment = struct {
    allocator: std.mem.Allocator,
    next: ?*Environment,
    values: std.StringHashMap(*Value),

    pub fn init(allocator: std.mem.Allocator) !*Environment {
        const e = try allocator.create(Environment);
        e.* = .{ .allocator = allocator, .next = null, .values = std.StringHashMap(*Value).init(allocator) };
        return e;
    }

    pub fn deinit(self: *Environment) void {
        self.values.deinit();
        var allocator = self.allocator;
        allocator.destroy(self);

        // defer self.allocator.destroy(self);
        // if (self.next) |n| {
        //     n.deinit();
        // }
    }

    pub fn push(self: *Environment) Environment {
        var new_environment = Environment.init(self.allocator);
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

pub fn cons(allocator: std.mem.Allocator, vcar: ?*Value, vcdr: ?*Value) *Value {
    const cs = allocator.create(Value) catch |err| {
        std.debug.panic("Panicked at Error: {any}", .{err});
    };
    cs.* = .{ .cons = .{ .car = vcar, .cdr = vcdr } };
    return cs;
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const str = Value.stringify(allocator, val) catch return;
    defer allocator.free(str);
    std.debug.print("{s}\n", .{str});
}
