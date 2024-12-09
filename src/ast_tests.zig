const std = @import("std");
const ast = @import("ast.zig");

const testing = std.testing;
const allocator = std.testing.allocator;

test "testing ast values" {
    {
        const s = try ast.sym(allocator, "hello");
        defer ast.deinit(s, allocator);
        try testing.expectEqualStrings(s.*.symbol.lexeme, "hello");
    }
    {
        const s = try ast.num(allocator, 123.0);
        defer ast.deinit(s, allocator);
        try testing.expectEqual(s.*.number.num, 123.0);
    }
}

test "binary expressions" {
    const s = try ast.binexp(allocator, try ast.num(allocator, 1.0), try ast.sym(allocator, "+"), try ast.num(allocator, 2.0));
    defer ast.deinit(s, allocator);
    try testing.expectEqual(s.*.binexp.a.*.number.num, 1.0);
    try testing.expectEqual(s.*.binexp.b.*.number.num, 2.0);
}

test "unary expressions" {
    const s = try ast.unexp(allocator, try ast.sym(allocator, "-"), try ast.num(allocator, 2.0));
    defer ast.deinit(s, allocator);
    try testing.expectEqualStrings(s.*.unexp.op.*.symbol.lexeme, "-");
    try testing.expectEqual(s.*.unexp.value.*.number.num, 2.0);
}

test "function definitions" {
    var c = try ast.func(allocator, try ast.sym(allocator, "test"), std.ArrayList(*ast.Ast).init(allocator), try ast.num(allocator, 1.0));
    defer ast.deinit(c, allocator);
    try c.func.addArg(try ast.sym(allocator, "a"));
    try c.func.addArg(try ast.sym(allocator, "b"));
    try testing.expectEqualStrings(c.*.func.sym.?.symbol.lexeme, "test");
    try testing.expectEqual(c.*.func.body.number.num, 1.0);
}
