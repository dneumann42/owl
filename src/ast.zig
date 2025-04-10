const std = @import("std");
const v = @import("values.zig");
const g = @import("gc.zig");
const Gc = g.Gc;
const Value = v.Value;

pub const Node = union(enum) {
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
    dot: Pair,
    binexp: Binexp,
    unexp: Unexp,
    block: std.ArrayList(*Ast),
    assignment: Pair,
    definition: Pair,
    use: Use,
};

pub const Meta = struct {
    line: u32 = 0,
    column: u32 = 0,
};
pub const Ast = struct { meta: Meta, node: Node };
pub const Call = struct {
    callable: *Ast,
    args: std.ArrayList(*Ast),
};
pub const Use = struct { name: []const u8 };
pub const Pair = struct { a: *Ast, b: *Ast };
pub const Dictionary = std.ArrayList(Pair);
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
    branches: std.ArrayList(Branch),
    otherwise: ?*Ast,
};
pub const Branch = struct { check: *Ast, then: *Ast };
pub const Binexp = struct { a: *Ast, op: *Ast, b: *Ast };
pub const Unexp = struct {
    op: *Ast,
    value: *Ast,
};

pub fn deinit(ast: *Ast, allocator: std.mem.Allocator) void {
    switch (ast.node) {
        .binexp => {
            deinit(ast.node.binexp.a, allocator);
            deinit(ast.node.binexp.b, allocator);
            deinit(ast.node.binexp.op, allocator);
        },
        .unexp => {
            deinit(ast.node.unexp.op, allocator);
            deinit(ast.node.unexp.value, allocator);
        },
        .func => {
            for (ast.node.func.args.items) |a| {
                deinit(a, allocator);
            }
            ast.node.func.args.deinit();
            if (ast.node.func.sym) |s| {
                deinit(s, allocator);
            }
        },
        .call => {
            for (ast.node.call.args.items) |a| {
                deinit(a, allocator);
            }
            ast.node.call.args.deinit();
            deinit(ast.node.call.callable, allocator);
        },
        .block => {
            for (ast.node.block.items) |item| {
                deinit(item, allocator);
            }
            ast.node.block.deinit();
        },
        .dot => {
            deinit(ast.node.dot.a, allocator);
            deinit(ast.node.dot.b, allocator);
        },
        .definition => {
            deinit(ast.node.definition.a, allocator);
            deinit(ast.node.definition.b, allocator);
        },
        .assignment => {
            deinit(ast.node.assignment.a, allocator);
            deinit(ast.node.assignment.b, allocator);
        },
        .ifx => {
            if (ast.node.ifx.otherwise) |el| {
                deinit(el, allocator);
            }
            for (ast.node.ifx.branches.items) |branch| {
                deinit(branch.check, allocator);
                deinit(branch.then, allocator);
            }
            ast.node.ifx.branches.deinit();
        },
        .whilex => {
            deinit(ast.node.whilex.condition, allocator);
            deinit(ast.node.whilex.block, allocator);
        },
        .forx => {
            deinit(ast.node.forx.variable, allocator);
            deinit(ast.node.forx.iterable, allocator);
            deinit(ast.node.forx.block, allocator);
        },
        .dictionary => {
            for (ast.node.dictionary.items) |kv| {
                deinit(kv.a, allocator);
                deinit(kv.b, allocator);
            }
            ast.node.dictionary.deinit();
        },
        .list => {
            for (ast.node.list.items) |item| {
                deinit(item, allocator);
            }
            ast.node.list.deinit();
        },
        .string => |s| {
            allocator.free(s);
        },
        .symbol => |s| {
            allocator.free(s);
        },
        .use => |u| {
            allocator.free(u.name);
        },
        .number, .boolean => {},
    }

    allocator.destroy(ast);
}

pub fn toString(node: *Ast, allocator: std.mem.Allocator) ![]const u8 {
    return toStringIdent(node, allocator, try std.fmt.allocPrint(allocator, "", .{}));
}

pub fn toStringIdent(node: *Ast, allocator: std.mem.Allocator, i: []const u8) error{OutOfMemory}![]const u8 {
    var lines = std.ArrayList([]const u8).init(allocator);

    switch (node.*) {
        .symbol => |s| try lines.append(try std.fmt.allocPrint(allocator, "#{s}", .{s})),
        .number => |n| try lines.append(try std.fmt.allocPrint(allocator, "(num {d})", .{n})),
        .boolean => |b| try lines.append(try std.fmt.allocPrint(allocator, "(bool {any})", .{b})),
        .string => |s| try lines.append(try std.fmt.allocPrint(allocator, "(str \"{s}\")", .{s})),
        .list => |ls| {
            var xs = std.ArrayList([]const u8).init(allocator);
            defer xs.deinit();
            try xs.append("[");
            var index: i32 = 0;
            var indent = i;
            var indent_updated = false;
            for (ls.items) |sub_node| {
                const s = try toStringIdent(sub_node, allocator, indent);
                if (index == 0) {
                    try xs.append(try std.fmt.allocPrint(allocator, "{s}", .{s}));
                } else {
                    try xs.append(try std.fmt.allocPrint(allocator, "{s} {s}", .{ indent, s }));
                }
                if (index > 0 and !indent_updated) {
                    indent_updated = true;
                    indent = try std.fmt.allocPrint(allocator, "{s}  ", .{indent});
                }
                if (index < ls.items.len - 1) {
                    try xs.append("\n");
                }
                index += 1;
            }
            try xs.append("]");
            try lines.append(try std.mem.join(allocator, "", xs.items));
        },
        .dictionary => |ls| {
            var xs = std.ArrayList([]const u8).init(allocator);
            defer xs.deinit();
            try xs.append("{");
            var index: i32 = 0;
            var indent = i;
            var indent_updated = false;
            for (ls.items) |sub_node| {
                const ks = try toStringIdent(sub_node.key, allocator, indent);
                const vs = try toStringIdent(sub_node.value, allocator, indent);
                if (index == 0) {
                    try xs.append(try std.fmt.allocPrint(allocator, "{s}: {s}", .{ ks, vs }));
                } else {
                    try xs.append(try std.fmt.allocPrint(allocator, "{s}{s}: {s}", .{ indent, ks, vs }));
                }
                if (!indent_updated) {
                    indent_updated = true;
                    indent = try std.fmt.allocPrint(allocator, "{s}  ", .{indent});
                }
                if (index < ls.items.len - 1) {
                    try xs.append("\n");
                }
                index += 1;
            }
            try xs.append("}");
            try lines.append(try std.mem.join(allocator, "", xs.items));
        },
        .call => try lines.append(try std.fmt.allocPrint(allocator, "(call)", .{})),
        .func => |fun| {
            try lines.append(try std.fmt.allocPrint(allocator, "(func {s})", .{fun.sym.?.symbol}));
        },
        .ifx => try lines.append(try std.fmt.allocPrint(allocator, "(if)", .{})),
        .whilex => try lines.append(try std.fmt.allocPrint(allocator, "(while)", .{})),
        .forx => try lines.append(try std.fmt.allocPrint(allocator, "(for)", .{})),
        .dot => try lines.append(try std.fmt.allocPrint(allocator, "(.)", .{})),
        .binexp => try lines.append(try std.fmt.allocPrint(allocator, "(binexp)", .{})),
        .unexp => try lines.append(try std.fmt.allocPrint(allocator, "(unexp)", .{})),
        .block => |ls| {
            var xs = std.ArrayList([]const u8).init(allocator);
            defer xs.deinit();
            try xs.append("[|");
            var index: i32 = 0;
            var indent = i;
            var indent_updated = false;
            for (ls.items) |sub_node| {
                const s = try toStringIdent(sub_node, allocator, indent);
                if (index == 0) {
                    try xs.append(try std.fmt.allocPrint(allocator, "{s}", .{s}));
                } else {
                    try xs.append(try std.fmt.allocPrint(allocator, "{s}{s}", .{ indent, s }));
                }
                if (!indent_updated) {
                    indent_updated = true;
                    indent = try std.fmt.allocPrint(allocator, "{s}  ", .{indent});
                }
                if (index < ls.items.len - 1) {
                    try xs.append("\n");
                }
                index += 1;
            }
            try xs.append("|]");
            try lines.append(try std.mem.join(allocator, "", xs.items));
        },
        .assignment => try lines.append(try std.fmt.allocPrint(allocator, "(assign)", .{})),
        .definition => |def| {
            const left = try toString(def.a, allocator);
            const indent = try allocator.alloc(u8, 10 + left.len);
            for (0..indent.len) |idx| {
                indent[idx] = ' ';
            }
            const right = try toStringIdent(def.b, allocator, indent);
            try lines.append(try std.fmt.allocPrint(allocator, "(define {s} {s})", .{ left, right }));
        },
        .use => |u| {
            try lines.append(try std.fmt.allocPrint(allocator, "(use {s})", .{u.name}));
        },
    }

    return std.mem.join(allocator, "\n", lines.items);
}

pub fn new(allocator: std.mem.Allocator, node: Node, meta: Meta) !*Ast {
    const ast = try allocator.create(Ast);
    ast.* = .{ .meta = meta, .node = node };
    return ast;
}

pub fn sym(allocator: std.mem.Allocator, lexeme: []const u8, meta: Meta) !*Ast {
    return new(allocator, .{ .symbol = lexeme }, meta);
}

pub fn symAlloc(allocator: std.mem.Allocator, s: []const u8, meta: Meta) !*Ast {
    const copy = try allocator.alloc(u8, s.len);
    @memcpy(copy, s);
    return sym(allocator, copy, meta);
}

pub fn num(allocator: std.mem.Allocator, number: f64, meta: Meta) !*Ast {
    return new(allocator, .{ .number = number }, meta);
}

pub fn str(allocator: std.mem.Allocator, lexeme: []const u8, meta: Meta) !*Ast {
    return new(allocator, .{ .string = lexeme }, meta);
}

pub fn strAlloc(allocator: std.mem.Allocator, s: []const u8, meta: Meta) !*Ast {
    const copy = try allocator.alloc(u8, s.len);
    @memcpy(copy, s);
    return str(allocator, copy, meta);
}

pub fn T(allocator: std.mem.Allocator, meta: Meta) !*Ast {
    return new(allocator, .{ .boolean = true }, meta);
}

pub fn F(allocator: std.mem.Allocator, meta: Meta) !*Ast {
    return new(allocator, .{ .boolean = false }, meta);
}

pub fn binexp(allocator: std.mem.Allocator, a: *Ast, op: *Ast, b: *Ast, meta: Meta) !*Ast {
    return new(allocator, .{ .binexp = .{ .a = a, .b = b, .op = op } }, meta);
}

pub fn unexp(allocator: std.mem.Allocator, op: *Ast, value: *Ast, meta: Meta) !*Ast {
    return new(allocator, .{ .unexp = .{ .op = op, .value = value } }, meta);
}

pub fn block(allocator: std.mem.Allocator, xs: std.ArrayList(*Ast), meta: Meta) !*Ast {
    return new(allocator, .{ .block = xs }, meta);
}

pub fn func(allocator: std.mem.Allocator, name: ?*Ast, args: std.ArrayList(*Ast), body: *Ast, meta: Meta) !*Ast {
    return new(allocator, .{ .func = .{
        .sym = name,
        .args = args,
        .body = body,
    } }, meta);
}

pub fn call(allocator: std.mem.Allocator, callable: *Ast, args: std.ArrayList(*Ast), meta: Meta) !*Ast {
    return new(allocator, .{ .call = .{
        .callable = callable,
        .args = args,
    } }, meta);
}

pub fn dot(allocator: std.mem.Allocator, a: *Ast, b: *Ast, meta: Meta) !*Ast {
    return new(allocator, .{ .dot = .{
        .a = a,
        .b = b,
    } }, meta);
}

pub fn ifx(allocator: std.mem.Allocator, branches: std.ArrayList(Branch), otherwise: ?*Ast, meta: Meta) !*Ast {
    return new(allocator, .{ .ifx = .{
        .branches = branches,
        .otherwise = otherwise,
    } }, meta);
}

pub fn whilex(allocator: std.mem.Allocator, cond: *Ast, blk: *Ast, meta: Meta) !*Ast {
    return new(allocator, .{ .whilex = .{ .block = blk, .condition = cond } }, meta);
}

pub fn forx(allocator: std.mem.Allocator, variable: *Ast, iterable: *Ast, blk: *Ast, meta: Meta) !*Ast {
    return new(allocator, .{ .forx = .{ .variable = variable, .iterable = iterable, .block = blk } }, meta);
}

pub fn define(allocator: std.mem.Allocator, symbol: *Ast, value: *Ast, meta: Meta) !*Ast {
    return new(allocator, .{ .definition = .{
        .a = symbol,
        .b = value,
    } }, meta);
}

pub fn assign(allocator: std.mem.Allocator, symbol: *Ast, value: *Ast, meta: Meta) !*Ast {
    return new(allocator, .{ .assignment = .{
        .a = symbol,
        .b = value,
    } }, meta);
}

pub fn use(allocator: std.mem.Allocator, name: []const u8, meta: Meta) !*Ast {
    return new(allocator, .{ .use = .{ .name = name } }, meta);
}

pub fn dict(allocator: std.mem.Allocator, pairs: std.ArrayList(Pair), meta: Meta) !*Ast {
    return new(allocator, .{ .dictionary = pairs }, meta);
}

pub fn list(allocator: std.mem.Allocator, vals: std.ArrayList(*Ast), meta: Meta) !*Ast {
    return new(allocator, .{ .list = vals }, meta);
}
