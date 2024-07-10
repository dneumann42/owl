const std = @import("std");
const r = @import("reader.zig");
const v = @import("values.zig");
const e = @import("evaluation.zig");
const expect = std.testing.expect;
const gc = @import("gc.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var G = gc.Gc.init(std.testing.allocator, gpa.allocator());

//test "reading blocks" {
//    var reader = r.Reader.initLoad(&G, " $(a + b + c) ");
//    const block = try reader.readBlock();
//    defer G.destroyAll();
//    v.repr(block);
//}

test "gc" {
    const n = try G.create(.{ .number = 42.0 });
    try expect(n.number == 42.0);
    G.destroyAll();
}

test "skipping whitespace" {
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
    return error.SkipZigTest;
}

test "reading symbols" {
    {
        var reader = r.Reader.initLoad(&G, "hello");
        const val = try reader.readSymbol();
        try expect(std.mem.eql(u8, val.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(reader.atEof());
    }
    {
        var reader = r.Reader.initLoad(&G, "hello ");
        const val = try reader.readSymbol();
        try expect(std.mem.eql(u8, val.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(!reader.atEof());
    }
    G.destroyAll();
    return error.SkipZigTest;
}

test "reading boolean literals" {
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
    G.destroyAll();
    return error.SkipZigTest;
}

test "reading string literals" {
    var reader = r.Reader.initLoad(&G, "\"Hello, World!\"");
    const val = try reader.readString();
    try expect(std.mem.eql(u8, val.string, "Hello, World!"));
    G.destroyAll();
    return error.SkipZigTest;
}

test "reading numbers" {
    var reader = r.Reader.initLoad(&G, "123");
    const val = try reader.readNumber();
    try expect(val.number == 123.0);
    try expect(reader.it == 3.0);
    G.destroyAll();
    return error.SkipZigTest;
}

test "reading unary operators" {
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
    G.destroyAll();
    return error.SkipZigTest;
}

test "reading unary expressions" {
    var reader = r.Reader.initLoad(&G, "-1");
    const val = try reader.readUnary();
    const s = v.car(val) orelse unreachable;
    try expect(std.mem.eql(u8, s.symbol, "-"));
    const n = v.car(v.cdr(val)) orelse unreachable;
    try expect(n.number == 1.0);
    G.destroyAll();
    return error.SkipZigTest;
}

test "reading binary expressions" {
    var reader = r.Reader.initLoad(&G, "1 or 2 or 3");
    const exp = try reader.readExpression();

    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "or"));
    G.destroyAll();
    return error.SkipZigTest;
}

test "reading function calls" {
    var reader = r.Reader.initLoad(&G, "call(x, y)");
    defer G.destroyAll();
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "call"));
    try expect(std.mem.eql(u8, exp.cons.cdr.?.cons.car.?.symbol, "x"));
    try expect(std.mem.eql(u8, exp.cons.cdr.?.cons.cdr.?.cons.car.?.symbol, "y"));
    return error.SkipZigTest;
}

test "reading function definitions" {
    var reader = r.Reader.initLoad(&G, "fun add-1(y) $(y + 1)");
    defer G.destroyAll();
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "fun"));
    try expect(std.mem.eql(u8, exp.cons.cdr.?.cons.car.?.symbol, "add-1"));
}

// Evaluation Tests

test "evaluating numbers" {
    const env = try v.Environment.init(&G);
    const value = try e.eval(env, "123");
    try expect(value.number == 123.0);
    G.destroyAll();
    return error.SkipZigTest;
}

test "evaluating symbols" {
    const env = try v.Environment.init(&G);
    const n = v.Value.num(&G, 123.0) catch unreachable;
    try env.set("hello", n);
    const s = v.Value.sym(&G, "hello") catch unreachable;
    const value = try e.evaluate(env, s);
    try expect(value.number == 123.0);
    G.destroyAll();
    return error.SkipZigTest;
}

test "evaluating code" {
    const env = try v.Environment.init(&G);
    const n = v.Value.num(&G, 123.0) catch unreachable;
    try env.set("hello", n);

    const value = try e.eval(env, "hello");
    try expect(value.number == 123.0);
    G.destroyAll();
    return error.SkipZigTest;
}

test "evaluating binary expressions" {
    const env = try v.Environment.init(&G);
    const value = try e.eval(env, "1 + 2");
    try expect(value.number == 3.0);
    G.destroyAll();
    return error.SkipZigTest;
}

test "garbage collection" {
    var g = gc.Gc.init(std.testing.allocator, gpa.allocator());
    defer g.destroyAll();
    const num = try g.create(.{ .number = 1.23 });
    try expect(num.number == 1.23);
    const header = gc.Gc.getHeader(num);
    try expect(header.marked == false);
    return error.SkipZigTest;
}
