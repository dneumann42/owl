const std = @import("std");

pub const ValueType = enum { nothing, number, string, symbol, boolean, cons };

pub const Cons = struct { car: ?*Value, cdr: ?*Value };

pub const Value = union(ValueType) {
    nothing: void,
    number: f64,
    string: []const u8,
    symbol: []const u8, // TODO intern
    boolean: bool,
    cons: Cons,

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
