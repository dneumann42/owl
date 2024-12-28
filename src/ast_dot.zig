const ast = @import("ast.zig");
const std = @import("std");
const pretty = @import("pretty");

pub fn wrapInBlock(allocator: std.mem.Allocator, block: []const u8, inner: []const u8) ![]const u8 {
    var strs = std.ArrayList([]const u8).init(allocator);
    defer strs.deinit();
    try strs.append(block);
    try strs.append(inner);
    try strs.append("}");
    return std.mem.join(allocator, "\n", strs.items);
}

pub fn buildGraphvizFromAst(allocator: std.mem.Allocator, node: *ast.Ast) ![]const u8 {
    pretty.print(allocator, node, .{ .max_depth = 100 }) catch unreachable;
    var context = Context{ .allocator = allocator, .id = 0 };
    const node_str = try buildNode(&context, node);
    return wrapInBlock(allocator, "digraph {", node_str);
}

pub fn buildAndWriteGraphvizFromAst(allocator: std.mem.Allocator, node: *ast.Ast) !void {
    const contents = try buildGraphvizFromAst(allocator, node);
    const file = try std.fs.cwd().createFile("ast.dot", .{});
    defer file.close();
    try file.writeAll(contents);
}

const Context = struct {
    id: i64,
    allocator: std.mem.Allocator,

    fn next_id(self: *Context) i64 {
        self.id += 1;
        return self.id;
    }

    fn next_id_alloc(self: *Context, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{d}", .{self.next_id()});
    }
};

pub fn buildNode(context: *Context, node: *ast.Ast) ![]const u8 {
    return switch (node.*) {
        .block => buildBlock(context, node),
        .call => buildCall(context, node),
        else => buildValue(context, node),
    };
}

pub fn buildValue(context: *Context, node: *ast.Ast) error{OutOfMemory}![]const u8 {
    var strs = std.ArrayList([]const u8).init(context.allocator);
    defer strs.deinit();
    try strs.append("value");
    try strs.append(try context.next_id_alloc(context.allocator));
    try strs.append(" [label=\"");

    switch (node.*) {
        .boolean => |b| {
            if (b) {
                try strs.append("true");
            } else {
                try strs.append("false");
            }
        },
        .number => |n| {
            const nstr = try std.fmt.allocPrint(context.allocator, "{d}", .{n});
            try strs.append(nstr);
        },
        .string => |s| {
            try strs.append(s);
        },
        else => {},
    }

    try strs.append("\"]\n");
    return std.mem.join(context.allocator, "", strs.items);
}

pub fn buildBlock(context: *Context, node: *ast.Ast) error{OutOfMemory}![]const u8 {
    var strs = std.ArrayList([]const u8).init(context.allocator);
    defer strs.deinit();
    try strs.append("Block {");
    for (node.block.items) |sub| {
        const sub_str = try buildNode(context, sub);
        try strs.append(sub_str);
    }
    try strs.append("}");
    return std.mem.join(context.allocator, "\n", strs.items);
}

pub fn buildCall(context: *Context, node: *ast.Ast) error{OutOfMemory}![]const u8 {
    const call = node.call;

    var strs = std.ArrayList([]const u8).init(context.allocator);
    defer strs.deinit();

    const identifier: ?[]const u8 = switch (call.callable.*) {
        .symbol => |s| s,
        else => null,
    };

    try strs.append("call");
    try strs.append(try context.next_id_alloc(context.allocator));
    try strs.append(" [shape=box, style=rounded, ");
    try strs.append("label=\"");
    try strs.append(identifier orelse "call");
    try strs.append("\"]");

    try strs.append(" {\n");
    if (identifier == null) {
        try strs.append("callable -> {\n");
        try strs.append("}\n");
    }
    try strs.append("args -> {\n");

    for (call.args.items) |arg| {
        const s = try buildNode(context, arg);
        try strs.append(s);
        try strs.append("\n");
    }

    try strs.append("}\n");
    try strs.append("}\n");

    return std.mem.join(context.allocator, "", strs.items);
}
