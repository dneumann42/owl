const std = @import("std");
const json = std.json;
const gc = @import("gc.zig");

pub const ValueType = enum { nothing, number, string, symbol, boolean, cons };

pub const Cons = struct { car: ?*Value, cdr: ?*Value };

pub const Value = union(ValueType) {
    nothing: void,
    number: f64,
    string: []const u8,
    symbol: []const u8, // TODO intern
    boolean: bool,
    cons: Cons,

    pub fn num(g: gc.Gc, n: f64) !*Value {
        return g.create(.{ .number = n });
    }

    pub fn sym(g: gc.Gc, s: []const u8) !*Value {
        return g.create(.{ .symbol = s });
    }

    pub fn True(g: gc.Gc) !*Value {
        return g.create(.{ .boolean = true });
    }

    pub fn False(g: gc.Gc) !*Value {
        return g.create(.{ .boolean = false });
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

    pub fn to_number(self: *const Value) f64 {
        return switch (self.*) {
            .number => self.number,
            else => 0.0,
        };
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
    gc: gc.Gc,
    next: ?*Environment,
    values: std.StringHashMap(*Value),

    pub fn init(g: gc.Gc) !*Environment {
        const e = try g.allocator.create(Environment);
        e.* = .{ .gc = g, .next = null, .values = std.StringHashMap(*Value).init(g.allocator) };
        return e;
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

pub fn cons(g: gc.Gc, vcar: ?*Value, vcdr: ?*Value) *Value {
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const str = Value.stringify(allocator, val) catch return;
    defer allocator.free(str);
    std.debug.print("{s}\n", .{str});
}
