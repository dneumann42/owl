const std = @import("std");
const r = @import("reader.zig");
const v = @import("values.zig");
const e = @import("evaluation.zig");
const expect = std.testing.expect;
const gc = @import("gc.zig");

const allocator = std.heap.page_allocator;

test "skipping whitespace" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    {
        var reader = r.Reader.initLoad(&G, "  \n\t X ");
        reader.skipWhitespace();
        try expect(reader.chr() == 'X');
    }
    {
        var reader = r.Reader.initLoad(&G, "  \n\t ");
        reader.skipWhitespace();
        try expect(reader.atEof());
    }
}

test "reading symbols" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    {
        var reader = r.Reader.initLoad(&G, "hello");
        const val = try reader.readSymbol(false);
        try expect(std.mem.eql(u8, val.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(reader.atEof());
    }
    {
        var reader = r.Reader.initLoad(&G, "hello ");
        const val = try reader.readSymbol(false);
        try expect(std.mem.eql(u8, val.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(!reader.atEof());
    }
}

test "reading boolean literals" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    {
        var reader = r.Reader.initLoad(&G, "true");
        const val = try reader.readBoolean();
        try expect(val.isBoolean());
        try expect(val.isTrue());
    }
    {
        var reader = r.Reader.initLoad(&G, "false");
        const val = try reader.readBoolean();
        try expect(val.isBoolean());
        try expect(val.isFalse());
    }
}

test "reading string literals" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "\"Hello, World!\"");
    const val = try reader.readString();
    try expect(std.mem.eql(u8, val.string, "Hello, World!"));
}

test "reading numbers" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "123");
    const val = try reader.readNumber();
    try expect(val.number == 123.0);
    try expect(reader.it == 3.0);
}

test "reading unary operators" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    {
        var reader = r.Reader.initLoad(&G, "-");
        const val = try reader.readUnaryOperator();
        try expect(std.mem.eql(u8, val.symbol, "-"));
    }
    {
        var reader = r.Reader.initLoad(&G, "not");
        const val = try reader.readUnaryOperator();
        try expect(std.mem.eql(u8, val.symbol, "not"));
    }
}

test "reading unary expressions" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "-1");
    const val = try reader.readUnary();
    const s = v.car(val) orelse unreachable;
    try expect(std.mem.eql(u8, s.symbol, "-"));
    const n = v.car(v.cdr(val)) orelse unreachable;
    try expect(n.number == 1.0);
}

test "reading binary expressions" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "1 or 2 or 3");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "or"));
}

test "reading function calls" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "call(x, y)");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "call"));
    try expect(std.mem.eql(u8, exp.cons.cdr.?.cons.car.?.symbol, "x"));
    try expect(std.mem.eql(u8, exp.cons.cdr.?.cons.cdr.?.cons.car.?.symbol, "y"));
}

test "reading function definitions" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "fun add-1(y) y + 1 end");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.function.name.?.symbol, "add-1"));
    try expect(std.mem.eql(u8, exp.function.params.cons.car.?.symbol, "y"));
    try expect(std.mem.eql(u8, exp.function.body.cons.car.?.symbol, "do"));
}

test "reading if expressions" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "if true then 1 end");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "cond"));

    const pair = v.car(exp.cons.cdr.?).?;
    const a = v.car(pair).?;
    const b = v.cdr(pair).?;

    try expect(a.boolean == true);
    try expect(b.cons.cdr.?.cons.car.?.number == 1.0);
}

test "reading if expressions with else" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "if false then 1 else 2 end");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "cond"));

    const pair1 = v.car(exp.cons.cdr.?).?;
    const a1 = v.car(pair1).?;
    const b1 = v.cdr(pair1).?;

    const pair2 = v.car(v.cdr(exp.cons.cdr.?).?).?;
    const a2 = v.car(pair2).?;
    const b2 = v.cdr(pair2).?;

    try expect(a1.boolean == false);
    try expect(b1.cons.cdr.?.cons.car.?.number == 1.0);

    try expect(a2.boolean == true);
    try expect(b2.cons.cdr.?.cons.car.?.number == 2.0);
}

test "reading if expressions with elif" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "if true then 1 elif false then 2 end");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "cond"));

    const pair1 = v.car(exp.cons.cdr.?).?;
    const a1 = v.car(pair1).?;
    const b1 = v.cdr(pair1).?;

    const pair2 = v.car(v.cdr(exp.cons.cdr.?).?).?;
    const a2 = v.car(pair2).?;
    const b2 = v.cdr(pair2).?;

    try expect(a1.boolean == true);
    try expect(b1.cons.cdr.?.cons.car.?.number == 1.0);

    try expect(a2.boolean == false);
    try expect(b2.cons.cdr.?.cons.car.?.number == 2.0);
}

test "reading if expressions with elif & else" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "if false then 1 elif false then 2 else 3 end");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "cond"));

    const pair1 = v.car(exp.cons.cdr.?).?;
    const a1 = v.car(pair1).?;
    const b1 = v.cdr(pair1).?;

    const pair2 = v.car(v.cdr(exp.cons.cdr.?).?).?;
    const a2 = v.car(pair2).?;
    const b2 = v.cdr(pair2).?;

    const pair3 = v.car(v.cdr(v.cdr(exp.cons.cdr.?).?).?).?;
    const a3 = v.car(pair3).?;
    const b3 = v.cdr(pair3).?;

    try expect(a1.boolean == false);
    try expect(b1.cons.cdr.?.cons.car.?.number == 1.0);

    try expect(a2.boolean == false);
    try expect(b2.cons.cdr.?.cons.car.?.number == 2.0);

    try expect(a3.boolean == true);
    try expect(b3.cons.cdr.?.cons.car.?.number == 3.0);
}

test "reading dictionaries" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "{ .a 1 .b 2 }");
    _ = try reader.readExpression();
}

test "reading params" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "()");
    const exp = try reader.readParameterList();
    try expect(exp.cons.car == null);
    reader.load("(a)");
    const exp2 = try reader.readParameterList();
    try expect(std.mem.eql(u8, exp2.cons.car.?.symbol, "a"));
    reader.load("(a, b)");
    const exp3 = try reader.readParameterList();
    try expect(std.mem.eql(u8, exp3.cons.car.?.symbol, "a"));
    try expect(std.mem.eql(u8, exp3.cons.cdr.?.cons.car.?.symbol, "b"));
}

test "reading records" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    var reader = r.Reader.initLoad(&G, "record { .a 1 .b 2 }");
    const exp = try reader.readDictionary();
    std.debug.print("{?}", .{exp.cons.cdr.?.dictionary.static});
}
