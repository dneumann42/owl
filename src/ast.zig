const std = @import("std");
const v = @import("values.zig");
const g = @import("gc.zig");
const Gc = g.Gc;
const Value = v.Value;

const AstTag = enum { symbol, number, boolean, string, list, dictionary, call, func, ifx, whilex, forx, dot, binexp, unexp, block, assignment, definition, use };

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

pub const Meta = struct {
    line: usize = 0,
};

pub const MetaAst = struct { node: Ast, meta: Meta };

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
            deinit(ast.forx.block, allocator);
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
        .use => |u| {
            allocator.free(u.name);
        },
        .number, .boolean => {},
    }

    destroy(ast, allocator);
}

pub fn destroy(ast: *Ast, allocator: std.mem.Allocator) void {
    const meta_ast: *MetaAst = @fieldParentPtr("node", ast);
    allocator.destroy(meta_ast);
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
            const left = try toString(def.left, allocator);
            const indent = try allocator.alloc(u8, 10 + left.len);
            for (0..indent.len) |idx| {
                indent[idx] = ' ';
            }
            const right = try toStringIdent(def.right, allocator, indent);
            try lines.append(try std.fmt.allocPrint(allocator, "(define {s} {s})", .{ left, right }));
        },
        .use => |u| {
            try lines.append(try std.fmt.allocPrint(allocator, "(use {s})", .{u.name}));
        },
    }

    return std.mem.join(allocator, "\n", lines.items);
}

pub fn copyAst(node: *Ast, allocator: std.mem.Allocator) !*Ast {
    const meta = getAstMeta(node);

    switch (node.*) {
        .symbol => |s| {
            const sym_copy = try allocator.alloc(u8, s.len);
            @memcpy(sym_copy, s);
            return sym(allocator, sym_copy, meta);
        },
        .number => |n| {
            return num(allocator, n, meta);
        },
        .boolean => |b| {
            return if (b) T(allocator, meta) else F(allocator, meta);
        },
        .string => |s| {
            const str_copy = try allocator.alloc(u8, s.len);
            @memcpy(str_copy, s);
            return str(allocator, str_copy, meta);
        },
        .list => |ls| {
            var copied_items = std.ArrayList(*Ast).init(allocator);
            for (ls.items) |item| {
                const item_copy = try copyAst(item, allocator);
                try copied_items.append(item_copy);
            }
            return list(allocator, copied_items, meta);
        },
        .dictionary => |dict_items| {
            var copied_pairs = std.ArrayList(KV).init(allocator);
            for (dict_items.items) |kv| {
                const key_copy = try copyAst(kv.key, allocator);
                const value_copy = try copyAst(kv.value, allocator);
                try copied_pairs.append(KV{ .key = key_copy, .value = value_copy });
            }
            return dict(allocator, copied_pairs, meta);
        },
        .call => |c| {
            var copied_args = std.ArrayList(*Ast).init(allocator);
            for (c.args.items) |arg| {
                const arg_copy = try copyAst(arg, allocator);
                try copied_args.append(arg_copy);
            }
            const callable_copy = try copyAst(c.callable, allocator);
            return call(allocator, callable_copy, copied_args, meta);
        },
        .func => |f| {
            var copied_args = std.ArrayList(*Ast).init(allocator);
            for (f.args.items) |arg| {
                const arg_copy = try copyAst(arg, allocator);
                try copied_args.append(arg_copy);
            }
            const body_copy = try copyAst(f.body, allocator);
            const sym_copy = if (f.sym) |s| try copyAst(s, allocator) else null;
            return func(allocator, sym_copy, copied_args, body_copy, meta);
        },
        .ifx => |i| {
            var copied_branches = std.ArrayList(Branch).init(allocator);
            for (i.branches.items) |branch| {
                const check_copy = try copyAst(branch.check, allocator);
                const then_copy = try copyAst(branch.then, allocator);
                try copied_branches.append(Branch{ .check = check_copy, .then = then_copy });
            }
            const else_branch_copy = if (i.elseBranch) |e| try copyAst(e, allocator) else null;
            return ifx(allocator, copied_branches, else_branch_copy, meta);
        },
        .whilex => |w| {
            const condition_copy = try copyAst(w.condition, allocator);
            const block_copy = try copyAst(w.block, allocator);
            return whilex(allocator, condition_copy, block_copy, meta);
        },
        .forx => |f| {
            const variable_copy = try copyAst(f.variable, allocator);
            const iterable_copy = try copyAst(f.iterable, allocator);
            const block_copy = try copyAst(f.block, allocator);
            return forx(allocator, variable_copy, iterable_copy, block_copy, meta);
        },
        .dot => |d| {
            const a_copy = try copyAst(d.a, allocator);
            const b_copy = try copyAst(d.b, allocator);
            return dot(allocator, a_copy, b_copy, meta);
        },
        .binexp => |b| {
            const a_copy = try copyAst(b.a, allocator);
            const op_copy = try copyAst(b.op, allocator);
            const b_copy = try copyAst(b.b, allocator);
            return binexp(allocator, a_copy, op_copy, b_copy, meta);
        },
        .unexp => |u| {
            const op_copy = try copyAst(u.op, allocator);
            const value_copy = try copyAst(u.value, allocator);
            return unexp(allocator, op_copy, value_copy, meta);
        },
        .block => |blk| {
            var copied_items = std.ArrayList(*Ast).init(allocator);
            for (blk.items) |item| {
                const item_copy = try copyAst(item, allocator);
                try copied_items.append(item_copy);
            }
            return block(allocator, copied_items, meta);
        },
        .assignment => |a| {
            const left_copy = try copyAst(a.left, allocator);
            const right_copy = try copyAst(a.right, allocator);
            return assign(allocator, left_copy, right_copy, meta);
        },
        .definition => |d| {
            const left_copy = try copyAst(d.left, allocator);
            const right_copy = try copyAst(d.right, allocator);
            return define(allocator, left_copy, right_copy, meta);
        },
        .use => |u| {
            const name_copy = try allocator.alloc(u8, u.name.len);
            @memcpy(name_copy, u.name);
            return use(allocator, name_copy, meta);
        },
    }
}

pub fn create(allocator: std.mem.Allocator, node: Ast, meta: Meta) !*Ast {
    const meta_ast = try allocator.create(MetaAst);
    meta_ast.meta = meta;
    const ptr = &meta_ast.node;
    ptr.* = node;
    return ptr;
}

pub fn getAstMeta(node: *Ast) Meta {
    const meta_ast: *MetaAst = @fieldParentPtr("node", node);
    return meta_ast.meta;
}

pub fn sym(allocator: std.mem.Allocator, lexeme: []const u8, meta: Meta) !*Ast {
    return create(allocator, .{ .symbol = lexeme }, meta);
}

pub fn symAlloc(allocator: std.mem.Allocator, s: []const u8, meta: Meta) !*Ast {
    const copy = try allocator.alloc(u8, s.len);
    @memcpy(copy, s);
    return sym(allocator, copy, meta);
}

pub fn num(allocator: std.mem.Allocator, number: f64, meta: Meta) !*Ast {
    return create(allocator, .{ .number = number }, meta);
}

pub fn str(allocator: std.mem.Allocator, lexeme: []const u8, meta: Meta) !*Ast {
    return create(allocator, .{ .string = lexeme }, meta);
}

pub fn strAlloc(allocator: std.mem.Allocator, s: []const u8, meta: Meta) !*Ast {
    const copy = try allocator.alloc(u8, s.len);
    @memcpy(copy, s);
    return str(allocator, copy, meta);
}

pub fn T(allocator: std.mem.Allocator, meta: Meta) !*Ast {
    return create(allocator, .{ .boolean = true }, meta);
}

pub fn F(allocator: std.mem.Allocator, meta: Meta) !*Ast {
    return create(allocator, .{ .boolean = false }, meta);
}

pub fn binexp(allocator: std.mem.Allocator, a: *Ast, op: *Ast, b: *Ast, meta: Meta) !*Ast {
    return create(allocator, .{ .binexp = .{ .a = a, .b = b, .op = op } }, meta);
}

pub fn unexp(allocator: std.mem.Allocator, op: *Ast, value: *Ast, meta: Meta) !*Ast {
    return create(allocator, .{ .unexp = .{ .op = op, .value = value } }, meta);
}

pub fn block(allocator: std.mem.Allocator, xs: std.ArrayList(*Ast), meta: Meta) !*Ast {
    return create(allocator, .{ .block = xs }, meta);
}

pub fn func(allocator: std.mem.Allocator, name: ?*Ast, args: std.ArrayList(*Ast), body: *Ast, meta: Meta) !*Ast {
    return create(allocator, .{ .func = .{
        .sym = name,
        .args = args,
        .body = body,
    } }, meta);
}

pub fn call(allocator: std.mem.Allocator, callable: *Ast, args: std.ArrayList(*Ast), meta: Meta) !*Ast {
    return create(allocator, .{ .call = .{
        .callable = callable,
        .args = args,
    } }, meta);
}

pub fn dot(allocator: std.mem.Allocator, a: *Ast, b: *Ast, meta: Meta) !*Ast {
    return create(allocator, .{ .dot = .{
        .a = a,
        .b = b,
    } }, meta);
}

pub fn ifx(allocator: std.mem.Allocator, branches: std.ArrayList(Branch), elseBranch: ?*Ast, meta: Meta) !*Ast {
    return create(allocator, .{ .ifx = .{
        .branches = branches,
        .elseBranch = elseBranch,
    } }, meta);
}

pub fn whilex(allocator: std.mem.Allocator, cond: *Ast, blk: *Ast, meta: Meta) !*Ast {
    return create(allocator, .{ .whilex = .{ .block = blk, .condition = cond } }, meta);
}

pub fn forx(allocator: std.mem.Allocator, variable: *Ast, iterable: *Ast, blk: *Ast, meta: Meta) !*Ast {
    return create(allocator, .{ .forx = .{ .variable = variable, .iterable = iterable, .block = blk } }, meta);
}

pub fn define(allocator: std.mem.Allocator, symbol: *Ast, value: *Ast, meta: Meta) !*Ast {
    return create(allocator, .{ .definition = .{
        .left = symbol,
        .right = value,
    } }, meta);
}

pub fn assign(allocator: std.mem.Allocator, symbol: *Ast, value: *Ast, meta: Meta) !*Ast {
    return create(allocator, .{ .assignment = .{
        .left = symbol,
        .right = value,
    } }, meta);
}

pub fn use(allocator: std.mem.Allocator, name: []const u8, meta: Meta) !*Ast {
    return create(allocator, .{ .use = .{ .name = name } }, meta);
}

pub fn dict(allocator: std.mem.Allocator, pairs: std.ArrayList(KV), meta: Meta) !*Ast {
    return create(allocator, .{ .dictionary = pairs }, meta);
}

pub fn list(allocator: std.mem.Allocator, vals: std.ArrayList(*Ast), meta: Meta) !*Ast {
    return create(allocator, .{ .list = vals }, meta);
}
