const v = @import("values.zig");
const r = @import("reader.zig");
const std = @import("std");

const EvalError = error{ AllocError, InvalidValue, InvalidCall, UndefinedSymbol, ExpectedValue, ExpectedSymbol, ExpectedNumber, ExpectedCallable, ParseError, InvalidIf, InvalidKeyValue };

pub fn eval(env: *v.Environment, code: []const u8) EvalError!*v.Value {
    var reader = r.Reader.initLoad(env.gc, code);
    return evaluate(env, reader.readProgram() catch {
        return error.ParseError;
    });
}

pub fn nothing(env: *v.Environment) *v.Value {
    const memo = struct {
        var value: ?*v.Value = null;
    };
    if (memo.value == null) {
        memo.value = env.gc.create(v.Value.nothing) catch unreachable;
    }
    return memo.value orelse unreachable;
}

pub fn evaluate(env: *v.Environment, value: *v.Value) EvalError!*v.Value {
    return switch (value.*) {
        v.Value.number, v.Value.string, v.Value.nothing, v.Value.boolean, v.Value.dictionary => value,
        v.Value.symbol => |s| {
            if (env.find(s)) |val| {
                return val;
            } else {
                std.log.err("Undefined symbol: '{s}'\n", .{s});
                return error.UndefinedSymbol;
            }
        },
        v.Value.nativeFunction => {
            return value;
        },
        v.Value.function => |f| {
            if (f.name) |sym| {
                env.set(sym.symbol, value) catch return error.AllocError;
            }
            return value;
        },
        v.Value.cons => |list| {
            if (list.car) |car| {
                return switch (car.*) {
                    .symbol => evaluateForms(env, car.symbol, list.cdr),
                    else => error.ExpectedSymbol,
                };
            }
            return error.InvalidCall;
        },
    };
}

pub fn evaluateForms(env: *v.Environment, sym: []const u8, args: ?*v.Value) !*v.Value {
    if (std.mem.eql(u8, sym, "+")) {
        return evaluateAdd(env, args);
    } else if (std.mem.eql(u8, sym, "-")) {
        return evaluateSub(env, args);
    } else if (std.mem.eql(u8, sym, "*")) {
        return evaluateMul(env, args);
    } else if (std.mem.eql(u8, sym, "/")) {
        return evaluateDiv(env, args);
    } else if (std.mem.eql(u8, sym, "eq")) {
        return evaluateEql(env, args);
    } else if (std.mem.eql(u8, sym, "not-eq")) {
        return evaluateNotEql(env, args);
    } else if (std.mem.eql(u8, sym, "<")) {
        return evaluateLessThan(env, args);
    } else if (std.mem.eql(u8, sym, ">")) {
        return evaluateGreaterThan(env, args);
    } else if (std.mem.eql(u8, sym, "do")) {
        return evaluateDo(env, args);
    } else if (std.mem.eql(u8, sym, "if")) {
        return evaluateIf(env, args);
    } else if (std.mem.eql(u8, sym, "def")) {
        return evaluateDefinition(env, args);
    } else if (std.mem.eql(u8, sym, "set")) {
        return evaluateSet(env, args);
    } else if (std.mem.eql(u8, sym, "dict")) {
        return evaluateDictionary(env, args);
    } else if (std.mem.eql(u8, sym, "list")) {
        return evaluateList(env, args);
    } else if (std.mem.eql(u8, sym, "car")) {
        if (args) |xs| {
            if (xs.cons.car) |value| {
                return evaluate(env, value);
            }
            return env.gc.nothing();
        }
        return env.gc.nothing();
    } else if (std.mem.eql(u8, sym, "cdr")) {
        if (args) |xs| {
            if (xs.cons.cdr) |value| {
                return evaluate(env, value);
            }
            return env.gc.nothing();
        }
        return env.gc.nothing();
    } else {
        const call = env.find(sym) orelse {
            std.log.err("Undefined symbol: '{s}'.\n", .{sym});
            return error.UndefinedSymbol;
        };
        return evaluateCall(env, call, args);
    }
}

pub fn evaluateList(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var list = v.cons(env.gc, null, null);

    var it: ?*v.Value = args;
    while (it != null) : (it = it.?.cons.cdr) {
        if (it.?.cons.car) |value| {
            list = v.cons(env.gc, try evaluate(env, value), list);
        }
    }

    return list;
}

pub fn evaluateDictionary(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var dict = v.Dictionary.init(env.gc) catch return error.AllocError;
    while (it) |xs| {
        const key = xs.cons.car.?;
        it = xs.cons.cdr;
        if (it) |vs| {
            const value = try evaluate(env, vs.cons.car.?);
            dict.put(key, value) catch {
                return error.AllocError;
            };
        } else {
            return error.InvalidKeyValue;
        }
    }
    return env.gc.create(.{
        .dictionary = dict,
    }) catch {
        return error.AllocError;
    };
}

pub fn evaluateDefinition(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    const sym = args.?.cons.car.?;
    const exp = args.?.cons.cdr.?.cons.car.?;
    const value = try evaluate(env, exp);
    env.set(sym.symbol, value) catch {
        return error.AllocError;
    };
    return value;
}

pub fn evaluateSet(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    const sym = args.?.cons.car.?;
    const exp = args.?.cons.cdr.?.cons.car.?;
    const value = try evaluate(env, exp);
    env.set(sym.symbol, value) catch {
        return error.AllocError;
    };
    return value;
}

pub fn evaluateIf(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    const cond = args.?.cons.car orelse return error.InvalidValue;
    const cond_result = try evaluate(env, cond);
    if (cond_result.boolean) {
        const cons = args.?.cons.cdr.?.cons.car orelse return error.InvalidIf;
        return evaluate(env, cons);
    } else {
        const alt = args.?.cons.cdr.?.cons.cdr.?.cons.car orelse return error.InvalidIf;
        return evaluate(env, alt);
    }
    return error.InvalidValue;
}

pub fn evaluateDo(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it: ?*v.Value = args;
    while (it != null) {
        const value = it.?.cons.car;
        if (value != null) {
            const evaluated = try evaluate(env, value.?);
            it = it.?.cons.cdr;
            if (it == null) {
                return evaluated;
            }
        } else {
            it = it.?.cons.cdr;
        }
    }
    return error.InvalidValue;
}

pub fn evaluateLessThan(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    const arg = args orelse return error.InvalidValue;
    const a = try evaluate(env, arg.cons.car orelse return error.ExpectedNumber);
    const b = try evaluate(env, arg.cons.cdr.?.cons.car orelse return error.ExpectedNumber);
    return env.gc.create(.{ .boolean = a.number < b.number }) catch error.AllocError;
}

pub fn evaluateGreaterThan(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    const arg = args orelse return error.InvalidValue;
    const a = try evaluate(env, arg.cons.car orelse return error.ExpectedNumber);
    const b = try evaluate(env, arg.cons.cdr.?.cons.car orelse return error.ExpectedNumber);
    return env.gc.create(.{ .boolean = a.number > b.number }) catch error.AllocError;
}

pub fn evaluateAdd(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    var it = args;
    var total: f64 = 0.0;
    while (it) |c| {
        if (c.cons.car) |value| {
            const adder = try evaluate(env, value);
            total += adder.toNumber();
        }
        it = c.cons.cdr;
    }
    const n = v.Value.num(env.gc, total) catch {
        return error.AllocError;
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
        return error.AllocError;
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
                if (c.cons.cdr == null) {
                    return v.Value.num(env.gc, -other.toNumber()) catch error.AllocError;
                }
                total = other.toNumber();
            } else {
                total -= other.toNumber();
            }
        }
        it = c.cons.cdr;
        idx += 1;
    }
    const n = v.Value.num(env.gc, total) catch {
        return error.AllocError;
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
        return error.AllocError;
    };
    return n;
}

pub fn evaluateEql(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    const arg = args orelse return error.InvalidValue;
    const a = try evaluate(env, arg.cons.car orelse return error.ExpectedValue);
    const b = try evaluate(env, arg.cons.cdr.?.cons.car orelse return error.ExpectedValue);
    return v.Value.boole(env.gc, a.isEql(b)) catch error.AllocError;
}

pub fn evaluateNotEql(env: *v.Environment, args: ?*v.Value) EvalError!*v.Value {
    const arg = args orelse return error.InvalidValue;
    const a = try evaluate(env, arg.cons.car orelse return error.ExpectedValue);
    const b = try evaluate(env, arg.cons.cdr.?.cons.car orelse return error.ExpectedValue);
    return v.Value.boole(env.gc, !a.isEql(b)) catch error.AllocError;
}

pub fn evaluateCall(env: *v.Environment, call: *v.Value, args: ?*v.Value) !*v.Value {
    switch (call.*) {
        v.Value.nativeFunction => |nfun| {
            return nfun(env, args);
        },
        v.Value.function => |fun| {
            return evaluateFunction(env, &fun, args);
        },
        else => {
            return error.ExpectedCallable;
        },
    }
}

pub fn evaluateFunction(env: *v.Environment, call: *const v.Function, args: ?*v.Value) !*v.Value {
    var next = env.push() catch return error.InvalidValue;
    // NOTE: this environment will eventually live on the function, so we should not deinit
    // until all references are invalid
    defer next.deinit();

    if (args) |arguments| {
        var it: ?*v.Value = arguments;
        var ps: ?*v.Value = call.params;
        while (it != null and ps != null) : (it = it.?.cons.cdr) {
            defer ps = ps.?.cons.cdr;
            const param = ps.?.cons.car orelse return error.InvalidValue;
            const value = it.?.cons.car orelse return error.InvalidValue;
            next.set(param.symbol, try evaluate(next, value)) catch return error.InvalidValue;
        }
    }

    const result = evaluate(next, call.body);

    return result;
}
