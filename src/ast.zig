const std = @import("std");
const v = @import("values.zig");

const AstTag = enum { symbol, number, func, binexp, unexp, block };

pub const Ast = union(AstTag) { symbol: Symbol, number: Number, func: Func, binexp: Binexp, unexp: Unexp, block: std.ArrayList(*Ast) };

pub const Symbol = struct {
    lexeme: []const u8,
};

pub const Number = struct {
    num: f64,
};

pub const Func = struct {
    sym: ?[]const u8,
    args: std.ArrayList(*Ast),
    body: *Ast,

    pub fn addArg(self: *Func, a: *Ast) !void {
        return self.args.append(a);
    }
};

pub const Binexp = struct { a: *Ast, b: *Ast };

pub const Unexp = struct {
    op: *Ast,
    value: *Ast,
};

pub fn deinit(ast: *Ast, allocator: std.mem.Allocator) void {
    switch (ast.*) {
        .binexp => {
            deinit(ast.*.binexp.a, allocator);
            deinit(ast.*.binexp.b, allocator);
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
        },
        .block => {
            for (ast.block.items) |item| {
                deinit(item, allocator);
            }
            ast.*.block.deinit();
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

pub fn binexp(allocator: std.mem.Allocator, a: *Ast, b: *Ast) !*Ast {
    const s = try allocator.create(Ast);
    s.* = .{ .binexp = .{ .a = a, .b = b } };
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

pub fn func(allocator: std.mem.Allocator, name: []const u8, body: *Ast) !*Ast {
    const c = try allocator.create(Ast);
    c.* = .{ .func = .{
        .sym = name,
        .args = std.ArrayList(*Ast).init(allocator),
        .body = body,
    } };
    return c;
}
