const std = @import("std");
const v = @import("values.zig");
const g = @import("gc.zig");
const Gc = g.Gc;
const Value = v.Value;

const AstTag = enum { symbol, number, boolean, string, list, dictionary, call, func, ifx, dot, binexp, unexp, block, assignment, definition };

pub const Ast = union(AstTag) {
    symbol: []const u8, //
    number: f64,
    boolean: bool,
    string: []const u8,
    list: std.ArrayList(*Ast),
    dictionary: Dictionary,
    call: Call,
    func: Func,
    ifx: If,
    dot: Dot,
    binexp: Binexp,
    unexp: Unexp,
    block: std.ArrayList(*Ast),
    assignment: Assign,
    definition: Define,
};

pub const Call = struct {
    callable: *Ast,
    args: std.ArrayList(*Ast),
};

pub const Dot = struct { a: *Ast, b: *Ast };
pub const Assign = struct { left: *Ast, right: *Ast };
pub const Define = struct { left: *Ast, right: *Ast };

pub const KV = struct { key: *Ast, value: *Ast };
pub const Dictionary = std.ArrayList(KV);

pub const Func = struct {
    sym: ?*Ast,
    args: std.ArrayList(*Ast),
    body: *Ast,

    pub fn addArg(self: *Func, a: *Ast) !void {
        return self.args.append(a);
    }
};

pub const If = struct {
    branches: std.ArrayList(Branch), //
    elseBranch: ?*Ast,
};

pub const Branch = struct { check: *Ast, then: *Ast };

pub const Binexp = struct { a: *Ast, op: *Ast, b: *Ast };

pub const Unexp = struct {
    op: *Ast,
    value: *Ast,
};

pub fn deinit(ast: *Ast, allocator: std.mem.Allocator) void {
    switch (ast.*) {
        .binexp => {
            deinit(ast.*.binexp.a, allocator);
            deinit(ast.*.binexp.b, allocator);
            deinit(ast.*.binexp.op, allocator);
        },
        .unexp => {
            deinit(ast.*.unexp.op, allocator);
            deinit(ast.*.unexp.value, allocator);
        },
        .func => {
            for (ast.*.func.args.items) |a| {
                deinit(a, allocator);
            }
            ast.*.func.args.deinit();
            deinit(ast.*.func.body, allocator);
            if (ast.*.func.sym) |s| {
                deinit(s, allocator);
            }
        },
        .call => {
            for (ast.*.call.args.items) |a| {
                deinit(a, allocator);
            }
            ast.*.call.args.deinit();
            deinit(ast.*.call.callable, allocator);
        },
        .block => {
            for (ast.block.items) |item| {
                deinit(item, allocator);
            }
            ast.*.block.deinit();
        },
        .dot => {
            deinit(ast.*.dot.a, allocator);
            deinit(ast.*.dot.b, allocator);
        },
        .definition => {
            deinit(ast.*.definition.left, allocator);
            deinit(ast.*.definition.right, allocator);
        },
        .assignment => {
            deinit(ast.*.assignment.left, allocator);
            deinit(ast.*.assignment.right, allocator);
        },
        .ifx => {
            if (ast.ifx.elseBranch) |el| {
                deinit(el, allocator);
            }
            for (ast.ifx.branches.items) |branch| {
                deinit(branch.check, allocator);
                deinit(branch.then, allocator);
            }
            ast.ifx.branches.deinit();
        },
        .dictionary => {
            for (ast.dictionary.items) |kv| {
                deinit(kv.key, allocator);
                deinit(kv.value, allocator);
            }
            ast.dictionary.deinit();
        },
        .list => {
            for (ast.list.items) |item| {
                deinit(item, allocator);
            }
            ast.list.deinit();
        },
        else => {},
    }
    allocator.destroy(ast);
}

pub fn buildValueFromAst(gc: *Gc, node: *Ast) !*Value {
    return switch (node.*) {
        .number => |n| gc.num(n),
        .string => |s| gc.str(s),
        .boolean => |b| gc.boolean(b),
        .dictionary => |d| {
            var it: *Value = v.cons(gc, gc.sym("dict"), null);
            for (d.items) |kv| {
                const key = try buildValueFromAst(gc, kv.key);
                const value = try buildValueFromAst(gc, kv.value);
                it = v.cons(gc, v.cons(gc, key, value), it);
            }
            return it.reverse();
        },
        .list => |xs| {
            var it: *Value = v.cons(gc, gc.sym("list"), null);
            for (xs.items) |val| {
                const value = try buildValueFromAst(gc, val);
                it = v.cons(gc, value, it);
            }
            return it.reverse();
        },
        .symbol => |s| gc.sym(s),
        .func => |f| {
            var it = v.cons(gc, gc.sym("fun"), null);

            if (f.sym) |name| {
                const nameValue = try buildValueFromAst(gc, name);
                it = v.cons(gc, nameValue, it);
            } else {
                it = v.cons(gc, null, it);
            }

            var params: ?*Value = null;
            for (f.args.items) |arg| {
                params = v.cons(gc, gc.sym(arg.symbol), params);
            }
            if (params) |ps| {
                it = v.cons(gc, ps.reverse(), it);
            } else {
                it = v.cons(gc, v.cons(gc, null, null), it);
            }

            const bodyValue = try buildValueFromAst(gc, f.body);
            it = v.cons(gc, bodyValue, it);

            return it.reverse();
        },
        .binexp => |exp| {
            const op = try buildValueFromAst(gc, exp.op);
            const a = try buildValueFromAst(gc, exp.a);
            const b = try buildValueFromAst(gc, exp.b);
            return v.cons(gc, op, v.cons(gc, a, v.cons(gc, b, null)));
        },
        .block => |blk| {
            var it: ?*Value = v.cons(gc, gc.sym("do"), null);
            for (blk.items) |subNode| {
                const val = try buildValueFromAst(gc, subNode);
                it = v.cons(gc, val, it);
            }
            if (it) |ls| {
                return ls.reverse();
            }
            return v.nothing(gc);
        },
        .definition => |def| {
            const name = try buildValueFromAst(gc, def.left);
            const value = try buildValueFromAst(gc, def.right);
            return v.cons(gc, gc.sym("def"), v.cons(gc, name, v.cons(gc, value, null)));
        },
        .assignment => |as| {
            const name = try buildValueFromAst(gc, as.left);
            const value = try buildValueFromAst(gc, as.right);
            return v.cons(gc, gc.sym("set"), v.cons(gc, name, v.cons(gc, value, null)));
        },
        .call => |cal| {
            const callable = try buildValueFromAst(gc, cal.callable);
            var it = v.cons(gc, callable, null);
            for (cal.args.items) |arg| {
                const argValue = try buildValueFromAst(gc, arg);
                it = v.cons(gc, argValue, it);
            }
            return it.reverse();
        },
        .unexp => |un| {
            const op = try buildValueFromAst(gc, un.op);
            const value = try buildValueFromAst(gc, un.value);
            return v.cons(gc, op, v.cons(gc, value, null));
        },
        .dot => |d| {
            const a = try buildValueFromAst(gc, d.a);
            const b = try buildValueFromAst(gc, d.b);
            return v.cons(gc, gc.sym("."), v.cons(gc, a, b));
        },
        .ifx => |i| {
            var it = v.cons(gc, gc.sym("cond"), null);

            for (i.branches.items) |branch| {
                const cond = try buildValueFromAst(gc, branch.check);
                const then = try buildValueFromAst(gc, branch.then);
                const pair = v.cons(gc, cond, then);
                it = v.cons(gc, pair, it);
            }

            if (i.elseBranch) |branch| {
                const then = try buildValueFromAst(gc, branch);
                const pair = v.cons(gc, gc.boolean(true), then);
                it = v.cons(gc, pair, it);
            }

            return it.reverse();
        },
    };
}

pub fn sym(allocator: std.mem.Allocator, lexeme: []const u8) !*Ast {
    const s = try allocator.create(Ast);
    s.* = .{ .symbol = lexeme };
    return s;
}

pub fn num(allocator: std.mem.Allocator, number: f64) !*Ast {
    const s = try allocator.create(Ast);
    s.* = .{ .number = number };
    return s;
}

pub fn str(allocator: std.mem.Allocator, lexeme: []const u8) !*Ast {
    const s = try allocator.create(Ast);
    s.* = .{ .string = lexeme };
    return s;
}

pub fn T(allocator: std.mem.Allocator) !*Ast {
    const b = try allocator.create(Ast);
    b.* = .{ .boolean = true };
    return b;
}

pub fn F(allocator: std.mem.Allocator) !*Ast {
    const b = try allocator.create(Ast);
    b.* = .{ .boolean = false };
    return b;
}

pub fn binexp(allocator: std.mem.Allocator, a: *Ast, op: *Ast, b: *Ast) !*Ast {
    const s = try allocator.create(Ast);
    s.* = .{ .binexp = .{ .a = a, .b = b, .op = op } };
    return s;
}

pub fn unexp(allocator: std.mem.Allocator, op: *Ast, value: *Ast) !*Ast {
    const s = try allocator.create(Ast);
    s.* = .{ .unexp = .{ .op = op, .value = value } };
    return s;
}

pub fn block(allocator: std.mem.Allocator, xs: std.ArrayList(*Ast)) !*Ast {
    const s = try allocator.create(Ast);
    s.* = .{ .block = xs };
    return s;
}

pub fn func(allocator: std.mem.Allocator, name: ?*Ast, args: std.ArrayList(*Ast), body: *Ast) !*Ast {
    const c = try allocator.create(Ast);
    c.* = .{ .func = .{
        .sym = name,
        .args = args,
        .body = body,
    } };
    return c;
}

pub fn call(allocator: std.mem.Allocator, callable: *Ast, args: std.ArrayList(*Ast)) !*Ast {
    const c = try allocator.create(Ast);
    c.* = .{ .call = .{
        .callable = callable,
        .args = args,
    } };
    return c;
}

pub fn dot(allocator: std.mem.Allocator, a: *Ast, b: *Ast) !*Ast {
    const c = try allocator.create(Ast);
    c.* = .{ .dot = .{
        .a = a,
        .b = b,
    } };
    return c;
}

pub fn ifx(allocator: std.mem.Allocator, branches: std.ArrayList(Branch), elseBranch: ?*Ast) !*Ast {
    const f = try allocator.create(Ast);
    f.* = .{ .ifx = .{
        .branches = branches,
        .elseBranch = elseBranch,
    } };
    return f;
}

pub fn define(allocator: std.mem.Allocator, symbol: *Ast, value: *Ast) !*Ast {
    const d = try allocator.create(Ast);
    d.* = .{ .definition = .{
        .left = symbol,
        .right = value,
    } };
    return d;
}

pub fn assign(allocator: std.mem.Allocator, symbol: *Ast, value: *Ast) !*Ast {
    const d = try allocator.create(Ast);
    d.* = .{ .assignment = .{
        .left = symbol,
        .right = value,
    } };
    return d;
}

pub fn dict(allocator: std.mem.Allocator, pairs: std.ArrayList(KV)) !*Ast {
    const d = try allocator.create(Ast);
    d.* = .{ .dictionary = pairs };
    return d;
}

pub fn list(allocator: std.mem.Allocator, vals: std.ArrayList(*Ast)) !*Ast {
    const xs = try allocator.create(Ast);
    xs.* = .{ .list = vals };
    return xs;
}
