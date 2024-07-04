const v = @import("values.zig");
const r = @import("reader.zig");
const std = @import("std");

const EvalError = error{InvalidValue};

pub fn evaluate(env: *v.Environment, value: *v.Value) !*v.Value {
    return switch (value.*) {
        v.Value.number, v.Value.string, v.Value.nothing, v.Value.boolean => value,
        v.Value.symbol => |s| {
            if (env.find(s)) |val| {
                return val;
            } else {
                return error.InvalidValue;
            }
        },
        else => error.InvalidValue,
    };
}

pub fn eval(env: *v.Environment, code: []const u8) !*v.Value {
    var reader = r.Reader.init_load(env.allocator, code);
    const val = try reader.read_expression();
    defer env.allocator.destroy(val);
    return evaluate(env, val);
}
