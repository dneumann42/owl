const std = @import("std");
const r = @import("reader.zig");
const v = @import("values.zig");
const eval = @import("evaluation.zig");
const expect = std.testing.expect;
const a = std.testing.allocator;

test "skipping whitespace" {
    {
        var reader = r.Reader.init_load(a, "  \n\t X ");
        reader.skip_whitespace();
        try expect(reader.chr() == 'X');
    }
    {
        var reader = r.Reader.init_load(a, "  \n\t ");
        reader.skip_whitespace();
        try expect(reader.at_eof());
    }
}

test "reading symbols" {
    {
        var reader = r.Reader.init_load(a, "hello");
        const val = try reader.read_symbol();
        defer reader.deinit(val);
        try expect(std.mem.eql(u8, val.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(reader.at_eof());
    }
    {
        var reader = r.Reader.init_load(a, "hello ");
        const val = try reader.read_symbol();
        defer reader.deinit(val);
        try expect(std.mem.eql(u8, val.symbol, "hello"));
        try expect(reader.it == 5);
        try expect(!reader.at_eof());
    }
}

test "reading boolean literals" {
    {
        var reader = r.Reader.init_load(a, "true");
        const val = try reader.read_boolean();
        defer reader.deinit(val);
        try expect(val.is_boolean());
        try expect(val.is_true());
    }
    {
        var reader = r.Reader.init_load(std.testing.allocator, "false");
        const val = try reader.read_boolean();
        defer reader.deinit(val);
        try expect(val.is_boolean());
        try expect(val.is_false());
    }
}

test "reading string literals" {
    var reader = r.Reader.init_load(std.testing.allocator, "\"Hello, World!\"");
    const val = try reader.read_string();
    defer reader.deinit(val);
    try expect(std.mem.eql(u8, val.string, "Hello, World!"));
}

test "reading numbers" {
    var reader = r.Reader.init_load(std.testing.allocator, "123");
    const val = try reader.read_number();
    defer reader.deinit(val);
    try expect(val.number == 123.0);
}

test "reading unary operators" {
    {
        var reader = r.Reader.init_load(std.testing.allocator, "-");
        const val = try reader.read_unary_operator();
        defer reader.deinit(val);
        try expect(std.mem.eql(u8, val.symbol, "-"));
    }
    {
        var reader = r.Reader.init_load(std.testing.allocator, "not");
        const val = try reader.read_unary_operator();
        defer reader.deinit(val);
        try expect(std.mem.eql(u8, val.symbol, "not"));
    }
}

test "reading unary expressions" {
    var reader = r.Reader.init_load(std.testing.allocator, "-1");
    const val = try reader.read_unary();
    defer reader.deinit(val);
    const s = v.car(val) orelse unreachable;
    try expect(std.mem.eql(u8, s.symbol, "-"));
    const n = v.car(v.cdr(val)) orelse unreachable;
    try expect(n.number == 1.0);
}

test "reading binary expressions" {
    var reader = r.Reader.init_load(std.testing.allocator, "1 or 2 or 3");
    const val = try reader.read_expression();
    defer reader.deinit(val);

    var it = val;
    const item1 = v.car(it) orelse unreachable;
    try expect(std.mem.eql(u8, item1.symbol, "or"));
    it = v.cdr(it) orelse unreachable;

    const item2 = v.car(it) orelse unreachable;
    try expect(item2.number == 1.0);
    it = v.cdr(it) orelse unreachable;

    const item3 = v.car(it) orelse unreachable;
    try expect(std.mem.eql(u8, item3.symbol, "or"));
    it = v.cdr(it) orelse unreachable;

    const item4 = v.car(it) orelse unreachable;
    try expect(item4.number == 2.0);
    it = v.cdr(it) orelse unreachable;

    const item5 = v.car(it) orelse unreachable;
    try expect(item5.number == 3.0);
    try expect(v.cdr(it) == null);
}

// Evaluation Tests

test "evaluating symbols" {
    var env = try v.Environment.init(a);
    defer env.deinit();
    const n = v.Value.num(a, 123.0) catch unreachable;
    defer a.destroy(n);
    try env.set("hello", n);
    const s = v.Value.sym(a, "hello") catch unreachable;
    defer a.destroy(s);
    const value = try eval.evaluate(env, s);
    try expect(value.number == 123.0);
}

test "evaluating code" {
    var env = try v.Environment.init(a);
    defer env.deinit();
    const n = v.Value.num(a, 123.0) catch unreachable;
    defer a.destroy(n);
    try env.set("hello", n);

    const value = try eval.eval(env, "hello");
    try expect(value.number == 123.0);
}
