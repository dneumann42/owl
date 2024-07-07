const v = @import("values.zig");
const r = @import("reader.zig");
const std = @import("std");

const EvalError = error{InvalidValue};

pub fn eval(env: *v.Environment, code: []const u8) !*v.Value {
    var reader = r.Reader.initLoad(env.gc, code);
    const val = try reader.readExpression();
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
                            return evaluateAdd(env, list.cdr);
                        } else if (std.mem.eql(u8, car.symbol, "-")) {
                            return evaluateSub(env, list.cdr);
                        } else if (std.mem.eql(u8, car.symbol, "*")) {
                            return evaluateMul(env, list.cdr);
                        } else if (std.mem.eql(u8, car.symbol, "/")) {
                            return evaluateDiv(env, list.cdr);
                        } else if (std.mem.eql(u8, car.symbol, "echo")) {
                            const val = list.cdr orelse unreachable;
                            v.repr(val);
                            return value;
                        } else {
                            const call = env.find(car.symbol) orelse return error.InvalidValue;
                            return evaluateCall(env, call, list.cdr);
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

pub fn evaluateAdd(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var total: f64 = 0.0;
    while (it) |c| {
        v.repr(c);
        if (c.cons.car) |value| {
            const adder = try evaluate(env, value);
            total += adder.toNumber();
        }
        it = c.cons.cdr;
    }
    const n = v.Value.num(env.gc, total) catch {
        return error.InvalidValue;
    };
    return n;
}

pub fn evaluateMul(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var total: f64 = 1.0;
    while (it) |c| {
        if (c.cons.car) |value| {
            const adder = try evaluate(env, value);
            total *= adder.toNumber();
        }
        it = c.cons.cdr;
    }
    const n = v.Value.num(env.gc, total) catch {
        return error.InvalidValue;
    };
    return n;
}

pub fn evaluateSub(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var total: f64 = undefined;
    var idx: i32 = 0;
    while (it) |c| {
        if (c.cons.car) |value| {
            const other = try evaluate(env, value);
            if (idx == 0) {
                total = other.toNumber();
            } else {
                total -= other.toNumber();
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

pub fn evaluateDiv(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var total: f64 = undefined;
    var idx: i32 = 0;
    while (it) |c| {
        if (c.cons.car) |value| {
            const other = try evaluate(env, value);
            if (idx == 0) {
                total = other.toNumber();
            } else {
                total /= other.toNumber();
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

pub fn evaluateCall(env: *v.Environment, call: *v.Value, args: ?*v.Value) !*v.Value {
    _ = env;
    _ = call;
    _ = args;
    return error.InvalidValue;
}
