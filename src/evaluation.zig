const v = @import("values.zig");
const std = @import("std");

const EvalError = error{InvalidValue};

pub fn evaluate(value: *v.Value) !*v.Value {
    return switch (value) {
        v.Value.number, v.Value.string, v.Value.nothing, v.Value.boolean => value,
        v.Value.symbol => error.InvalidValue,
        else => error.InvalidValue,
    };
}
