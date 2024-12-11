const std = @import("std");
const v = @import("values.zig");

const AstTag = enum { symbol, number, boolean, string, call, func, ifx, dot, binexp, unexp, block, assignment, definition };

pub const Ast = union(AstTag) { symbol: Symbol, number: Number, boolean: bool, string: []const u8, call: Call, func: Func, ifx: If, dot: Dot, binexp: Binexp, unexp: Unexp, block: std.ArrayList(*Ast), assignment: Assign, definition: Define };

pub const Symbol = struct {
    lexeme: []const u8,
};

pub const Number = struct {
    num: f64,
};

pub const Call = struct {
    callable: *Ast,
    args: std.ArrayList(*Ast),
};

pub const Dot = struct { a: *Ast, b: *Ast };
pub const Assign = struct { left: *Ast, right: *Ast };
pub const Define = struct { left: *Ast, right: *Ast };

pub const Func = struct {
    sym: ?*Ast,
    args: std.ArrayList(*Ast),
    body: *Ast,

    pub fn addArg(self: *Func, a: *Ast) !void {
        return self.args.append(a);
    }
};

pub const If = struct { branches: std.ArrayList(*Branch), elseBranch: ?*Ast };

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
        else => {},
    }
    allocator.destroy(ast);
}

pub fn sym(allocator: std.mem.Allocator, lexeme: []const u8) !*Ast {
    const s = try allocator.create(Ast);
    s.* = .{ .symbol = .{ .lexeme = lexeme } };
    return s;
}

pub fn num(allocator: std.mem.Allocator, number: f64) !*Ast {
    const s = try allocator.create(Ast);
    s.* = .{ .number = .{ .num = number } };
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
