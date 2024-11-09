const std = @import("std");
const v = @import("values.zig");

const AstTag = enum { symbol, number, call, binexp, unexp };

const Ast = union(AstTag) {
    symbol: Symbol,
    number: Number,
    call: Call,
    binexp: Binexp,
    unexp: Unexp,
};

const Symbol = struct {
    lexeme: []const u8,
};

const Number = struct {
    num: f64,
};

const Call = struct {
    sym: ?[]const u8,
    args: std.ArrayList(*Ast),
    body: *Ast,

    pub fn addArg(self: *Call, a: *Ast) !void {
        return self.args.append(a);
    }
};

const Binexp = struct { a: *Ast, b: *Ast };

const Unexp = struct {
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
        .call => {
            for (ast.*.call.args.items) |a| {
                deinit(a, allocator);
            }
            ast.*.call.args.deinit();
            deinit(ast.*.call.body, allocator);
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

pub fn call(allocator: std.mem.Allocator, name: []const u8, body: *Ast) !*Ast {
    const c = try allocator.create(Ast);
    c.* = .{ .call = .{
        .sym = name,
        .args = std.ArrayList(*Ast).init(allocator),
        .body = body,
    } };
    return c;
}
