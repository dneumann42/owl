const std = @import("std");

pub const ValueType = enum { nothing, number, string, symbol, boolean, list };

pub const Cons = struct { car: ?*Value, cdr: ?*Value };

pub const Value = union(ValueType) {
    nothing: void,
    number: f64,
    string: []const u8,
    symbol: []const u8, // TODO intern
    boolean: bool,
    list: Cons,

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

pub fn cons(allocator: std.mem.Allocator, car: *Value, cdr: *Value) *Value {
    const cs = allocator.create(Value);
    cs.* = .{ .cons = .{ .car = car, .cdr = cdr } };
    return cs;
}
