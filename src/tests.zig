const std = @import("std");
const r = @import("reader.zig");
const v = @import("values.zig");
const e = @import("evaluation.zig");
const expect = std.testing.expect;
const gc = @import("gc.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var G = gc.Gc.init(std.testing.allocator, gpa.allocator());

test "gc" {
    defer G.destroyAll();
    const n = try G.create(.{ .number = 42.0 });
    try expect(n.number == 42.0);
}

test "skipping whitespace" {
    defer G.destroyAll();
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
    defer G.destroyAll();
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
    defer G.destroyAll();
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
    defer G.destroyAll();
    var reader = r.Reader.initLoad(&G, "\"Hello, World!\"");
    const val = try reader.readString();
    try expect(std.mem.eql(u8, val.string, "Hello, World!"));
}

test "reading numbers" {
    defer G.destroyAll();
    var reader = r.Reader.initLoad(&G, "123");
    const val = try reader.readNumber();
    try expect(val.number == 123.0);
    try expect(reader.it == 3.0);
}

test "reading unary operators" {
    defer G.destroyAll();
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
    defer G.destroyAll();
    var reader = r.Reader.initLoad(&G, "-1");
    const val = try reader.readUnary();
    const s = v.car(val) orelse unreachable;
    try expect(std.mem.eql(u8, s.symbol, "-"));
    const n = v.car(v.cdr(val)) orelse unreachable;
    try expect(n.number == 1.0);
}

test "reading binary expressions" {
    defer G.destroyAll();
    var reader = r.Reader.initLoad(&G, "1 or 2 or 3");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "or"));
}

test "reading function calls" {
    defer G.destroyAll();
    var reader = r.Reader.initLoad(&G, "call(x, y)");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "call"));
    try expect(std.mem.eql(u8, exp.cons.cdr.?.cons.car.?.symbol, "x"));
    try expect(std.mem.eql(u8, exp.cons.cdr.?.cons.cdr.?.cons.car.?.symbol, "y"));
}

test "reading function definitions" {
    defer G.destroyAll();
    var reader = r.Reader.initLoad(&G, "fun add-1(y) y + 1 end");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.function.name.symbol, "add-1"));
    try expect(std.mem.eql(u8, exp.function.params.cons.car.?.symbol, "y"));
    try expect(std.mem.eql(u8, exp.function.body.cons.car.?.symbol, "do"));
}

test "reading if expressions" {
    defer G.destroyAll();
    var reader = r.Reader.initLoad(&G, "if true then 1 else 2 end");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "if"));
    try expect(exp.cons.cdr.?.cons.car.?.boolean == true);
    try expect(exp.cons.cdr.?.cons.cdr.?.cons.car.?.number == 1.0);
    try expect(exp.cons.cdr.?.cons.cdr.?.cons.cdr.?.cons.car.?.number == 2.0);
}

test "reading if expressions without else" {
    defer G.destroyAll();
    var reader = r.Reader.initLoad(&G, "if true then 1 end");
    const exp = try reader.readExpression();
    try expect(std.mem.eql(u8, exp.cons.car.?.symbol, "if"));
    try expect(exp.cons.cdr.?.cons.car.?.boolean == true);
    try expect(exp.cons.cdr.?.cons.cdr.?.cons.car.?.number == 1.0);
}

// Evaluation Tests

test "evaluating numbers" {
    defer G.destroyAll();
    const env = try v.Environment.init(&G);
    const value = try e.eval(env, "123");
    try expect(value.number == 123.0);
    G.destroyAll();
}

test "evaluating symbols" {
    defer G.destroyAll();
    const env = try v.Environment.init(&G);
    const n = v.Value.num(&G, 123.0) catch unreachable;
    try env.set("hello", n);
    const s = v.Value.sym(&G, "hello") catch unreachable;
    const value = try e.evaluate(env, s);
    try expect(value.number == 123.0);
}

test "evaluating code" {
    defer G.destroyAll();
    const env = try v.Environment.init(&G);
    const n = v.Value.num(&G, 123.0) catch unreachable;
    try env.set("hello", n);

    const value = try e.eval(env, "hello");
    try expect(value.number == 123.0);
}

test "evaluating binary expressions" {
    defer G.destroyAll();
    const env = try v.Environment.init(&G);
    const value = try e.eval(env, "1 + 2");
    try expect(value.number == 3.0);
}

test "evaluating function definitions and calls" {
    defer G.destroyAll();
    const env = try v.Environment.init(&G);
    const value = try e.eval(env,
        \\fun a(y) y + 1 end
        \\a(9)
    );
    try expect(value.number == 10.0);
}

test "garbage collection" {
    var g = gc.Gc.init(std.testing.allocator, gpa.allocator());
    defer g.destroyAll();
    const num = try g.create(.{ .number = 1.23 });
    try expect(num.number == 1.23);
    const header = gc.Gc.getHeader(num);
    try expect(header.marked == false);
}
