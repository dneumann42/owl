const r = @import("reader.zig");
const a = @import("ast.zig");
const g = @import("gc.zig");
const std = @import("std");
const testing = std.testing;

test "tokenization" {
    const reader = r.Tokenizer.init(testing.allocator,
        \\132 2 ()  [] {} if fun
        \\ "Hello"
    );
    const tokens = try reader.tokenize();
    defer tokens.deinit();
    try testing.expectEqual(tokens.items[0].kind, r.TokenKind.number);
    try testing.expectEqualStrings(reader.getLexeme(tokens.items[0]).?, "132");
    try testing.expectEqual(tokens.items[0].kind, r.TokenKind.number);
    try testing.expectEqual(tokens.items[1].kind, r.TokenKind.number);
    try testing.expectEqual(tokens.items[2].kind, r.TokenKind.openParen);
    try testing.expectEqual(tokens.items[3].kind, r.TokenKind.closeParen);
    try testing.expectEqual(tokens.items[4].kind, r.TokenKind.openBracket);
    try testing.expectEqual(tokens.items[5].kind, r.TokenKind.closeBracket);
    try testing.expectEqual(tokens.items[6].kind, r.TokenKind.openBrace);
    try testing.expectEqual(tokens.items[7].kind, r.TokenKind.closeBrace);
    try testing.expectEqual(tokens.items[8].kind, r.TokenKind.keyword);
    try testing.expectEqualStrings(reader.getLexeme(tokens.items[8]).?, "if");
    try testing.expectEqual(tokens.items[9].kind, r.TokenKind.keyword);
    try testing.expectEqualStrings(reader.getLexeme(tokens.items[9]).?, "fun");
    try testing.expectEqual(tokens.items[10].kind, r.TokenKind.string);
    try testing.expectEqualStrings(reader.getLexeme(tokens.items[10]).?,
        \\"Hello"
    );
}

test "comments and whitespace" {
    const reader = r.Tokenizer.init(testing.allocator,
        \\1 ;; hello
        \\(
    );
    const tokens = try reader.tokenize();
    defer tokens.deinit();
    try testing.expectEqual(tokens.items[0].kind, r.TokenKind.number);
    try testing.expectEqual(tokens.items[1].kind, r.TokenKind.openParen);
}

test "reading programs" {
    var reader = try r.Reader.init(testing.allocator, "1");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.node.block.items[0].node.number, 1.0);
}

test "reading number literals" {
    var reader = try r.Reader.init(testing.allocator, "31415926 1 2 3");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.node.block.items[0].node.number, 31415926);
    try testing.expectEqual(program.node.block.items[1].node.number, 1);
    try testing.expectEqual(program.node.block.items[2].node.number, 2);
    try testing.expectEqual(program.node.block.items[3].node.number, 3);
}

test "reading boolean literals" {
    var reader = try r.Reader.init(testing.allocator, "true false");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.node.block.items[0].node.boolean, true);
    try testing.expectEqual(program.node.block.items[1].node.boolean, false);
}

test "reading string literals" {
    var reader = try r.Reader.init(testing.allocator,
        \\"Hello, World!" ""
    );
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqualStrings(program.node.block.items[0].node.string, "Hello, World!");
    try testing.expectEqualStrings(program.node.block.items[1].node.string, "");
}

test "reading unary operators" {
    var reader = try r.Reader.init(testing.allocator, "not - x");
    defer reader.deinit();
    const aa = reader.readUnaryOperator().ok;
    defer a.deinit(aa, testing.allocator);
    const ab = reader.readUnaryOperator().ok;
    defer a.deinit(ab, testing.allocator);
    switch (reader.readUnaryOperator()) {
        .ok => {
            try testing.expect(false);
        },
        .err => {},
    }
}

test "reading unary expressions" {
    var reader = try r.Reader.init(testing.allocator, "-123");
    defer reader.deinit();
    const aa_result = reader.readUnary();
    const aa = aa_result.ok;
    defer a.deinit(aa, testing.allocator);
    try testing.expectEqualStrings(aa.node.unexp.op.node.symbol, "-");
    try testing.expectEqual(aa.node.unexp.value.node.number, 123);
}

test "reading binary expressions" {
    var reader = try r.Reader.init(testing.allocator, "1 or 2 and 3 4 + 5");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];
    try testing.expectEqual(exp.node.binexp.a.node.number, 1);
    try testing.expectEqualStrings(exp.node.binexp.op.node.symbol, "or");
    try testing.expectEqual(exp.node.binexp.b.node.binexp.a.node.number, 2);
    try testing.expectEqualStrings(exp.node.binexp.b.node.binexp.op.node.symbol, "and");
    try testing.expectEqual(exp.node.binexp.b.node.binexp.b.node.number, 3);

    const exp2 = program.node.block.items[1];
    try testing.expectEqual(exp2.node.binexp.a.node.number, 4);
    try testing.expectEqual(exp2.node.binexp.b.node.number, 5);
}

test "reading function calls" {
    var reader = try r.Reader.init(testing.allocator, "call(1, 2)");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);

    const exp = program.node.block.items[0];
    try testing.expectEqualStrings(exp.node.call.callable.node.symbol, "call");
    try testing.expectEqual(exp.node.call.args.items[0].node.number, 1);
    try testing.expectEqual(exp.node.call.args.items[1].node.number, 2);
}

test "reading dot & call expressions" {
    var reader = try r.Reader.init(testing.allocator, "a.b a().b a.b() a.b().c");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);

    const exp1 = program.node.block.items[0];
    try testing.expectEqualStrings(exp1.node.dot.a.node.symbol, "a");
    try testing.expectEqualStrings(exp1.node.dot.b.node.symbol, "b");

    const exp2 = program.node.block.items[1];
    try testing.expectEqualStrings(exp2.node.dot.a.node.call.callable.node.symbol, "a");
    try testing.expectEqualStrings(exp2.node.dot.b.node.symbol, "b");

    const exp3 = program.node.block.items[2];
    try testing.expectEqualStrings(exp3.node.call.callable.node.dot.a.node.symbol, "a");
    try testing.expectEqualStrings(exp3.node.call.callable.node.dot.b.node.symbol, "b");

    const exp4 = program.node.block.items[3];
    // try testing.expectEqualStrings(exp4.dot.a.symbol, "a");
    // try testing.expectEqualStrings(exp4.call.callable.dot.b.symbol, "b");
    try testing.expectEqualStrings(exp4.node.dot.b.node.symbol, "c");
}

test "reading nested dot expressions" {
    var reader = try r.Reader.init(testing.allocator, "a.b.c");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp1 = program.node.block.items[0];
    try testing.expectEqualStrings(exp1.node.dot.a.node.dot.a.node.symbol, "a");
    try testing.expectEqualStrings(exp1.node.dot.a.node.dot.b.node.symbol, "b");
    try testing.expectEqualStrings(exp1.node.dot.b.node.symbol, "c");
}

test "reading empty functions" {
    var reader = try r.Reader.init(testing.allocator, "fun a() end");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];
    try testing.expectEqualStrings(exp.node.func.sym.?.node.symbol, "a");
}

test "reading function definitions" {
    var reader = try r.Reader.init(testing.allocator, "fun add-1(y) y + 1 end");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];

    try testing.expectEqualStrings(exp.node.func.sym.?.node.symbol, "add-1");
    try testing.expectEqualStrings(exp.node.func.args.items[0].node.symbol, "y");
    const binexp = exp.node.func.body.node.block.items[0];
    try testing.expectEqualStrings(binexp.node.binexp.a.node.symbol, "y");
    try testing.expectEqualStrings(binexp.node.binexp.op.node.symbol, "+");
    try testing.expectEqual(binexp.node.binexp.b.node.number, 1);
}

test "reading lambdas" {
    var reader = try r.Reader.init(testing.allocator, "fn(y) y + 1");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];

    try testing.expectEqual(exp.node.func.sym, null);
    try testing.expectEqualStrings(exp.node.func.args.items[0].node.symbol, "y");
    const binexp = exp.node.func.body;
    try testing.expectEqualStrings(binexp.node.binexp.a.node.symbol, "y");
    try testing.expectEqualStrings(binexp.node.binexp.op.node.symbol, "+");
    try testing.expectEqual(binexp.node.binexp.b.node.number, 1);
}

test "reading definitions" {
    var reader = try r.Reader.init(testing.allocator, "x := 10");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];
    try testing.expectEqualStrings(exp.node.definition.a.node.symbol, "x");
    try testing.expectEqual(exp.node.definition.b.node.number, 10);
}

test "reading assignment" {
    var reader = try r.Reader.init(testing.allocator, "x = 10");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];
    try testing.expectEqualStrings(exp.node.assignment.a.node.symbol, "x");
    try testing.expectEqual(exp.node.assignment.b.node.number, 10);
}

test "reading do blocks" {
    var reader = try r.Reader.init(testing.allocator, "do 1 end");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];
    try testing.expect(exp.node.block.items.len == 1);
}

test "reading if" {
    var reader = try r.Reader.init(testing.allocator, "if true then 1 end");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];

    try testing.expectEqual(exp.node.ifx.otherwise, null);
    try testing.expectEqual(exp.node.ifx.branches.items.len, 1);
    try testing.expectEqual(exp.node.ifx.branches.items[0].check.node.boolean, true);
    try testing.expectEqual(exp.node.ifx.branches.items[0].then.node.block.items[0].node.number, 1);
}

test "reading if with else" {
    var reader = try r.Reader.init(testing.allocator, "if true then 1 else 2 end");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];
    try testing.expectEqual(exp.node.ifx.otherwise.?.node.block.items[0].node.number, 2);
    try testing.expectEqual(exp.node.ifx.branches.items.len, 1);
    try testing.expectEqual(exp.node.ifx.branches.items[0].check.node.boolean, true);
    try testing.expectEqual(exp.node.ifx.branches.items[0].then.node.block.items[0].node.number, 1);
}

test "reading if with elif and else" {
    var reader = try r.Reader.init(testing.allocator, "if true then 1 elif false then 3 else 2 end");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];
    try testing.expectEqual(exp.node.ifx.otherwise.?.node.block.items[0].node.number, 2);
    try testing.expectEqual(exp.node.ifx.branches.items.len, 2);
    try testing.expectEqual(exp.node.ifx.branches.items[0].check.node.boolean, true);
    try testing.expectEqual(exp.node.ifx.branches.items[0].then.node.block.items[0].node.number, 1);
    try testing.expectEqual(exp.node.ifx.branches.items[1].check.node.boolean, false);
    try testing.expectEqual(exp.node.ifx.branches.items[1].then.node.block.items[0].node.number, 3);
}

test "reading conditions" {
    var reader = try r.Reader.init(testing.allocator,
        \\cond
        \\  1 + 1 do 2 end
        \\  2     do 3 end
        \\end
    );
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];

    try testing.expectEqual(exp.node.ifx.otherwise, null);
    try testing.expectEqual(exp.node.ifx.branches.items.len, 2);
    try testing.expectEqual(exp.node.ifx.branches.items[0].check.node.binexp.a.node.number, 1);
    try testing.expectEqual(exp.node.ifx.branches.items[0].then.node.block.items[0].node.number, 2);
}

test "reading dictionary literals" {
    var reader = try r.Reader.init(testing.allocator, "{ a: 1 b: 2 }");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];

    try testing.expectEqual(exp.node.dictionary.items.len, 2);
    try testing.expectEqualStrings(exp.node.dictionary.items[0].a.node.symbol, "a");
    try testing.expectEqual(exp.node.dictionary.items[0].b.node.number, 1);
    try testing.expectEqualStrings(exp.node.dictionary.items[1].a.node.symbol, "b");
    try testing.expectEqual(exp.node.dictionary.items[1].b.node.number, 2);
}

test "reading list literals" {
    var reader = try r.Reader.init(testing.allocator, "[1 2 3]");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];

    try testing.expectEqual(exp.node.list.items[0].node.number, 1);
    try testing.expectEqual(exp.node.list.items[1].node.number, 2);
    try testing.expectEqual(exp.node.list.items[2].node.number, 3);
}

test "reading empty list literals" {
    var reader = try r.Reader.init(testing.allocator, "[]");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    const exp = program.node.block.items[0];

    try testing.expectEqual(exp.node.list.items.len, 0);
}

test "blocks" {
    var reader = try r.Reader.init(testing.allocator, "1 2 3");
    defer reader.deinit();
    const program = reader.read().ok;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.node.block.items[0].node.number, 1);
    try testing.expectEqual(program.node.block.items[1].node.number, 2);
    try testing.expectEqual(program.node.block.items[2].node.number, 3);
}
