const v = @import("values.zig");
const r = @import("reader.zig");
const std = @import("std");

const EvalError = error{InvalidValue};

pub fn eval(env: *v.Environment, code: []const u8) !*v.Value {
    var reader = r.Reader.init_load(env.gc, code);
    const val = try reader.read_expression();
    return evaluate(env, val);
}

pub fn evaluate(env: *v.Environment, value: *v.Value) !*v.Value {
    return switch (value.*) {
        v.Value.number, v.Value.string, v.Value.nothing, v.Value.boolean => value,
        v.Value.symbol => |s| {
            if (env.find(s)) |val| {
                // for now we will assume that the 'value' has been used and is no longer needed
                return val;
            } else {
                std.debug.print("ERROR: '{s}'\n", .{s});
                return error.InvalidValue;
            }
        },
        v.Value.cons => |list| {
            if (list.car) |car| {
                switch (car.*) {
                    .symbol => {
                        if (std.mem.eql(u8, car.symbol, "+")) {
                            return evaluate_add(env, list.cdr);
                        } else if (std.mem.eql(u8, car.symbol, "-")) {
                            return evaluate_sub(env, list.cdr);
                        } else if (std.mem.eql(u8, car.symbol, "*")) {
                            return evaluate_mul(env, list.cdr);
                        } else if (std.mem.eql(u8, car.symbol, "/")) {
                            return evaluate_div(env, list.cdr);
                        } else {
                            const call = env.find(car.symbol) orelse return error.InvalidValue;
                            return evaluate_call(env, call, list.cdr);
                        }
                    },
                    else => {
                        return error.InvalidValue;
                    },
                }
            }
            return error.InvalidValue;
        },
    };
}

pub fn evaluate_add(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var total: f64 = 0.0;
    while (it) |c| {
        v.repr(c);
        if (c.cons.car) |value| {
            const adder = try evaluate(env, value);
            total += adder.to_number();
        }
        it = c.cons.cdr;
    }
    const n = v.Value.num(env.gc, total) catch {
        return error.InvalidValue;
    };
    return n;
}

pub fn evaluate_mul(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var total: f64 = 1.0;
    while (it) |c| {
        if (c.cons.car) |value| {
            const adder = try evaluate(env, value);
            total *= adder.to_number();
        }
        it = c.cons.cdr;
    }
    const n = v.Value.num(env.gc, total) catch {
        return error.InvalidValue;
    };
    return n;
}

pub fn evaluate_sub(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var total: f64 = undefined;
    var idx: i32 = 0;
    while (it) |c| {
        if (c.cons.car) |value| {
            const other = try evaluate(env, value);
            if (idx == 0) {
                total = other.to_number();
            } else {
                total -= other.to_number();
            }
        }
        it = c.cons.cdr;
        idx += 1;
    }
    const n = v.Value.num(env.gc, total) catch {
        return error.InvalidValue;
    };
    return n;
}

pub fn evaluate_div(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var total: f64 = undefined;
    var idx: i32 = 0;
    while (it) |c| {
        if (c.cons.car) |value| {
            const other = try evaluate(env, value);
            if (idx == 0) {
                total = other.to_number();
            } else {
                total /= other.to_number();
            }
        }
        it = c.cons.cdr;
        idx += 1;
    }
    const n = v.Value.num(env.gc, total) catch {
        return error.InvalidValue;
    };
    return n;
}

pub fn evaluate_call(env: *v.Environment, call: *v.Value, args: ?*v.Value) !*v.Value {
    _ = env;
    _ = call;
    _ = args;
    return error.InvalidValue;
}
