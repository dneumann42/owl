const std = @import("std");
const v = @import("values.zig");
const g = @import("gc.zig");
const Gc = g.Gc;
const Value = v.Value;

const AstTag = enum { symbol, number, boolean, string, list, dictionary, call, func, ifx, whilex, forx, dot, binexp, unexp, block, assignment, definition, use };

// NOTE: the ast doesn't own any of the strings,
// it will give the strings to the values during evaluation

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
    whilex: While,
    forx: For,
    dot: Dot,
    binexp: Binexp,
    unexp: Unexp,
    block: std.ArrayList(*Ast),
    assignment: Assign,
    definition: Define,
    use: Use,
};

pub const Call = struct {
    callable: *Ast,
    args: std.ArrayList(*Ast),
};

pub const Use = struct { name: []const u8 };

pub const Dot = struct { a: *Ast, b: *Ast };
pub const Assign = struct { left: *Ast, right: *Ast };
pub const Define = struct { left: *Ast, right: *Ast };

pub const KV = struct { key: *Ast, value: *Ast };
pub const Dictionary = std.ArrayList(KV);
pub const While = struct { condition: *Ast, block: *Ast };
pub const For = struct { variable: *Ast, iterable: *Ast, block: *Ast };

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
        .whilex => {
            deinit(ast.whilex.condition, allocator);
            deinit(ast.whilex.block, allocator);
        },
        .forx => {
            deinit(ast.forx.variable, allocator);
            deinit(ast.forx.iterable, allocator);
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
        .string => |s| {
            allocator.free(s);
        },
        .symbol => |s| {
            allocator.free(s);
        },
        else => {},
    }
    allocator.destroy(ast);
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

pub fn whilex(allocator: std.mem.Allocator, cond: *Ast, blk: *Ast) !*Ast {
    const w = try allocator.create(Ast);
    w.* = .{ .whilex = .{ .block = blk, .condition = cond } };
    return w;
}

pub fn forx(allocator: std.mem.Allocator, variable: *Ast, iterable: *Ast, blk: *Ast) !*Ast {
    const f = try allocator.create(Ast);
    f.* = .{ .forx = .{ .variable = variable, .iterable = iterable, .block = blk } };
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

pub fn use(allocator: std.mem.Allocator, name: []const u8) !*Ast {
    const u = try allocator.create(Ast);
    u.* = .{ .use = .{ .name = name } };
    return u;
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
