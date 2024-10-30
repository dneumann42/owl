const v = @import("values.zig");
const r = @import("reader.zig");
const gc = @import("gc.zig");
const std = @import("std");
const assert = std.debug.assert;

pub const EvalError = error{ AllocError, InvalidValue, InvalidCall, UndefinedSymbol, ExpectedValue, ExpectedSymbol, ExpectedNumber, ExpectedCallable, ParseError, InvalidIf, InvalidKeyValue, MissingArguments };

pub fn eval(g: *gc.Gc, code: []const u8) EvalError!*v.Value {
    var reader = r.Reader.initLoad(g, code);
    return evaluate(g, reader.readProgram() catch {
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

pub fn evaluate(g: *gc.Gc, value: *v.Value) EvalError!*v.Value {
    return switch (value.*) {
        v.Value.number, v.Value.string, v.Value.nothing, v.Value.boolean, v.Value.dictionary => value,
        v.Value.symbol => |s| {
            if (g.env().find(s)) |val| {
                return val;
            } else {
                // std.log.err("Undefined symbol: '{s}'\n", .{s});
                return error.UndefinedSymbol;
            }
        },
        v.Value.nativeFunction => {
            return value;
        },
        v.Value.function => |f| {
            if (f.name) |sym| {
                g.env().set(sym.symbol, value) catch return error.AllocError;
            }
            const new_environment = v.Environment.init(g.allocator) catch unreachable;
            new_environment.next = g.env();
            value.function.env = new_environment;
            return value;
        },
        v.Value.cons => |list| {
            if (list.car) |car| {
                return switch (car.*) {
                    .symbol => evaluateSpecialForm(g, car.symbol, list.cdr),
                    else => {
                        const evaluated = try evaluate(g, car);
                        return switch (evaluated.*) {
                            .symbol => evaluateSpecialForm(g, evaluated.symbol, list.cdr),
                            .function => evaluateFunction(g, &evaluated.function, list.cdr),
                            else => error.ExpectedSymbol,
                        };
                    },
                };
            }
            return error.InvalidCall;
        },
    };
}

const FormFun = fn (*gc.Gc, ?*v.Value) EvalError!*v.Value;
const FormTable = struct { sym: []const u8, func: FormFun };
const specialForms = [_]FormTable{
    .{ .sym = "+", .func = evaluateAdd },
    .{ .sym = "-", .func = evaluateSub },
    .{ .sym = "*", .func = evaluateMul },
    .{ .sym = "/", .func = evaluateDiv },
    .{ .sym = "eq", .func = evaluateEql },
    .{ .sym = "not-eq", .func = evaluateNotEql },
    .{ .sym = "<", .func = evaluateLessThan },
    .{ .sym = ">", .func = evaluateGreaterThan },
    .{ .sym = "do", .func = evaluateDo },
    .{ .sym = "if", .func = evaluateIf },
    .{ .sym = "cond", .func = evaluateCond },
    .{ .sym = "def", .func = evaluateDefinition },
    .{ .sym = "set", .func = evaluateSet },
    .{ .sym = "dict", .func = evaluateDictionary },
    .{ .sym = "list", .func = evaluateList },
    .{ .sym = ".", .func = evaluateDot },

    .{ .sym = "cons", .func = evaluateCons },
    .{ .sym = "car", .func = evaluateCar },
    .{ .sym = "cdr", .func = evaluateCdr },

    .{ .sym = "head", .func = evaluateCar },
    .{ .sym = "tail", .func = evaluateCdr },
};

pub fn evaluateSpecialForm(g: *gc.Gc, sym: []const u8, args: ?*v.Value) !*v.Value {
    inline for (specialForms) |op| {
        if (std.mem.eql(u8, sym, op.sym)) {
            return op.func(g, args);
        }
    }
    if (std.mem.eql(u8, sym, "car")) {
        if (args) |xs| {
            if (xs.cons.car) |value| {
                return evaluate(g, value);
            }
            return g.nothing();
        }
        return g.nothing();
    } else if (std.mem.eql(u8, sym, "cdr")) {
        if (args) |xs| {
            if (xs.cons.cdr) |value| {
                return evaluate(g, value);
            }
            return g.nothing();
        }
        return g.nothing();
    } else {
        const call = g.env().find(sym) orelse {
            std.log.err("Undefined symbol: '{s}'.\n", .{sym});
            return error.UndefinedSymbol;
        };
        return evaluateCall(g, call, args);
    }
}

pub fn evaluateDot(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    if (args) |xs| {
        const a = try evaluate(g, xs.cons.car orelse g.nothing());
        const b = xs.cons.cdr.?.cons.car orelse g.nothing();
        const value = a.dictionary.get(b);
        if (value) |val| {
            return val;
        }
        return g.nothing();
    } else {
        return error.MissingArguments;
    }
    return g.nothing();
}

pub fn evaluateList(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    var list = v.cons(g, null, null);

    var it: ?*v.Value = args;
    while (it != null) : (it = it.?.cons.cdr) {
        if (it.?.cons.car) |value| {
            list = v.cons(g, try evaluate(g, value), list);
        }
    }

    return list;
}

pub fn evaluateCons(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    const a = try evaluate(g, v.car(args.?).?);
    const b = try evaluate(g, v.car(v.cdr(args.?).?).?);
    return v.cons(g, a, b);
}

pub fn evaluateCar(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    if (args == null) return g.nothing();
    const a = try evaluate(g, v.car(args.?) orelse g.nothing());
    return v.car(a) orelse g.nothing();
}

pub fn evaluateCdr(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    if (args == null) return g.nothing();
    const a = try evaluate(g, v.car(args.?) orelse g.nothing());
    return v.cdr(a) orelse g.nothing();
}

pub fn evaluateDictionary(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    // TODO: this form takes a dictionary value and evaluates its key and value
    // then yields the raw dictionary
    var it: ?*v.Value = args.?.dictionary.pairs;
    var dict = v.Dictionary.init(g) catch return error.AllocError;

    while (it != null) : (it = it.?.cons.cdr) {
        // this feels like a hack, why does the dictionary end in a `nothing`?
        if (it.?.cons.car == null and it.?.cons.cdr == null) {
            continue;
        }

        const pair = it.?.cons.car.?;
        const key = pair.cons.car;
        const value = pair.cons.cdr;

        dict.put(key.?, try evaluate(g, value.?)) catch {
            return error.AllocError;
        };
    }

    return g.create(.{ .dictionary = dict }) catch {
        return error.AllocError;
    };
}

pub fn evaluateDefinition(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    const sym = args.?.cons.car.?;
    const exp = args.?.cons.cdr.?.cons.car.?;
    const value = try evaluate(g, exp);
    g.env().set(sym.symbol, value) catch {
        return error.AllocError;
    };
    return value;
}

pub fn evaluateSet(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    const sym = args.?.cons.car.?;
    const exp = args.?.cons.cdr.?.cons.car.?;
    const value = try evaluate(g, exp);
    g.env().set(sym.symbol, value) catch {
        return error.AllocError;
    };
    return value;
}

pub fn evaluateIf(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    const cond = args.?.cons.car orelse return error.InvalidValue;
    const cond_result = try evaluate(g, cond);
    if (cond_result.boolean) {
        const cons = args.?.cons.cdr.?.cons.car orelse return error.InvalidIf;
        return evaluate(g, cons);
    } else {
        const alt = args.?.cons.cdr.?.cons.cdr.?.cons.car orelse return error.InvalidIf;
        return evaluate(g, alt);
    }
    return error.InvalidValue;
}

pub fn evaluateCond(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    var list = args;

    while (list != null) : (list = list.?.cons.cdr) {
        const cond = try evaluate(g, list.?.cons.car.?.cons.car.?);

        if (cond.boolean) {
            return evaluate(g, list.?.cons.car.?.cons.cdr.?);
        }
    }

    return g.nothing();
}

pub fn evaluateDo(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    var next = g.push();
    var it: ?*v.Value = args;

    while (it != null) {
        const value = it.?.cons.car;

        if (value == null) {
            it = it.?.cons.cdr;
            continue;
        }

        const evaluated = try evaluate(&next, value.?);
        it = it.?.cons.cdr;
        if (it == null) {
            return evaluated;
        }
    }

    return g.nothing();
}

pub fn evaluateLessThan(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    const arg = args orelse return error.InvalidValue;
    const a = try evaluate(g, arg.cons.car orelse return error.ExpectedNumber);
    const b = try evaluate(g, arg.cons.cdr.?.cons.car orelse return error.ExpectedNumber);
    return g.boolean(a.number < b.number);
}

pub fn evaluateGreaterThan(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    const arg = args orelse return error.InvalidValue;
    const a = try evaluate(g, arg.cons.car orelse return error.ExpectedNumber);
    const b = try evaluate(g, arg.cons.cdr.?.cons.car orelse return error.ExpectedNumber);
    return g.boolean(a.number > b.number);
}

pub fn evaluateAdd(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    if (args == null) return g.num(0);
    var it = args.?;
    var total: f64 = 0.0;
    while (it.cons.car) |value| : (it = it.cons.cdr orelse break) {
        const adder = try evaluate(g, value);
        total += adder.toNumber();
    }
    return g.num(total);
}

pub fn evaluateMul(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    if (args == null) return g.num(0);
    var it = args.?;
    var total: f64 = 1.0;
    while (it.cons.car) |value| : (it = it.cons.cdr orelse break) {
        const adder = try evaluate(g, value);
        total *= adder.toNumber();
    }
    return g.num(total);
}

pub fn evaluateSub(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    if (args == null) return g.num(0);
    var it = args.?;
    const first_value = (try evaluate(g, it.cons.car.?)).toNumber();
    if (it.cons.cdr == null) {
        return g.num(-first_value);
    }
    var total = first_value;
    it = it.cons.cdr.?;
    while (it.cons.car) |value| : (it = it.cons.cdr orelse break) {
        const other = (try evaluate(g, value)).toNumber();
        total -= other;
    }
    return g.num(total);
}

pub fn evaluateDiv(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    if (args == null) return g.num(0);
    var it = args.?;
    const first_value = (try evaluate(g, it.cons.car.?)).toNumber();
    if (it.cons.cdr == null) {
        return g.num(-first_value);
    }
    var total: f64 = first_value;
    it = it.cons.cdr.?;
    while (it.cons.car) |value| : (it = it.cons.cdr orelse break) {
        const other = (try evaluate(g, value)).toNumber();
        total /= other;
    }
    return g.num(total);
}

pub fn evaluateEql(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    const arg = args orelse return error.InvalidValue;
    const a = try evaluate(g, arg.cons.car orelse return error.ExpectedValue);
    const b = try evaluate(g, arg.cons.cdr.?.cons.car orelse return error.ExpectedValue);
    return g.boolean(a.isEql(b));
}

pub fn evaluateNotEql(g: *gc.Gc, args: ?*v.Value) EvalError!*v.Value {
    const arg = args orelse return error.InvalidValue;
    const a = try evaluate(g, arg.cons.car orelse return error.ExpectedValue);
    const b = try evaluate(g, arg.cons.cdr.?.cons.car orelse return error.ExpectedValue);
    return g.boolean(!a.isEql(b));
}

pub fn evaluateCall(g: *gc.Gc, call: *v.Value, args: ?*v.Value) !*v.Value {
    switch (call.*) {
        v.Value.nativeFunction => |nfun| {
            return nfun(g, args);
        },
        v.Value.function => |fun| {
            return evaluateFunction(g, &fun, args);
        },
        else => {
            return error.ExpectedCallable;
        },
    }
}

pub fn evaluateFunction(g: *gc.Gc, call: *const v.Function, args: ?*v.Value) !*v.Value {
    var next = g.withEnv(call.env);
    if (args) |arguments| {
        var it: ?*v.Value = arguments;
        var ps: ?*v.Value = call.params;
        while (it != null and ps != null) : (it = it.?.cons.cdr) {
            defer ps = ps.?.cons.cdr;
            const param = ps.?.cons.car orelse break;
            const value = it.?.cons.car orelse return error.InvalidValue;
            call.env.set(param.symbol, try evaluate(&next, value)) catch return error.InvalidValue;
        }
    }
    const result = evaluate(&next, call.body);
    return result;
}
