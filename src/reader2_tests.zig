const r = @import("reader2.zig");
const a = @import("ast.zig");
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
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.block.items[0].number.num, 1.0);
}

test "reading number literals" {
    var reader = try r.Reader.init(testing.allocator, "31415926 1 2 3");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.block.items[0].number.num, 31415926);
    try testing.expectEqual(program.block.items[1].number.num, 1);
    try testing.expectEqual(program.block.items[2].number.num, 2);
    try testing.expectEqual(program.block.items[3].number.num, 3);
}

test "reading boolean literals" {
    var reader = try r.Reader.init(testing.allocator, "true false");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.block.items[0].boolean, true);
    try testing.expectEqual(program.block.items[1].boolean, false);
}

test "reading string literals" {
    var reader = try r.Reader.init(testing.allocator,
        \\"Hello, World!" ""
    );
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqualStrings(program.block.items[0].string, "Hello, World!");
    try testing.expectEqualStrings(program.block.items[1].string, "");
}

test "reading unary operators" {
    var reader = try r.Reader.init(testing.allocator, "not - x");
    defer reader.deinit();
    const aa = reader.readUnaryOperator().success;
    defer a.deinit(aa, testing.allocator);
    const ab = reader.readUnaryOperator().success;
    defer a.deinit(ab, testing.allocator);
    switch (reader.readUnaryOperator()) {
        .success => {
            try testing.expect(false);
        },
        .failure => {},
    }
}

test "reading unary expressions" {
    var reader = try r.Reader.init(testing.allocator, "-123");
    defer reader.deinit();
    const aa_result = reader.readUnary();
    const aa = aa_result.success;
    defer a.deinit(aa, testing.allocator);
    try testing.expectEqualStrings(aa.unexp.op.symbol.lexeme, "-");
    try testing.expectEqual(aa.unexp.value.number.num, 123);
}

test "reading binary expressions" {
    var reader = try r.Reader.init(testing.allocator, "1 or 2 and 3 4 + 5");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];
    try testing.expectEqual(exp.binexp.a.number.num, 1);
    try testing.expectEqualStrings(exp.binexp.op.symbol.lexeme, "or");
    try testing.expectEqual(exp.binexp.b.binexp.a.number.num, 2);
    try testing.expectEqualStrings(exp.binexp.b.binexp.op.symbol.lexeme, "and");
    try testing.expectEqual(exp.binexp.b.binexp.b.number.num, 3);

    const exp2 = program.block.items[1];
    try testing.expectEqual(exp2.binexp.a.number.num, 4);
    try testing.expectEqual(exp2.binexp.b.number.num, 5);
}

test "reading function calls" {
    var reader = try r.Reader.init(testing.allocator, "call(1, 2)");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);

    const exp = program.block.items[0];
    try testing.expectEqualStrings(exp.call.callable.symbol.lexeme, "call");
    try testing.expectEqual(exp.call.args.items[0].number.num, 1);
    try testing.expectEqual(exp.call.args.items[1].number.num, 2);
}

test "reading dot & call expressions" {
    var reader = try r.Reader.init(testing.allocator, "a.b a().b a.b()");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);

    const exp1 = program.block.items[0];
    try testing.expectEqualStrings(exp1.dot.a.symbol.lexeme, "a");
    try testing.expectEqualStrings(exp1.dot.b.symbol.lexeme, "b");

    const exp2 = program.block.items[1];
    try testing.expectEqualStrings(exp2.dot.a.call.callable.symbol.lexeme, "a");
    try testing.expectEqualStrings(exp2.dot.b.symbol.lexeme, "b");

    const exp3 = program.block.items[2];
    try testing.expectEqualStrings(exp3.call.callable.dot.a.symbol.lexeme, "a");
    try testing.expectEqualStrings(exp3.call.callable.dot.b.symbol.lexeme, "b");
}

test "reading function definitions" {
    var reader = try r.Reader.init(testing.allocator, "fun add-1(y) y + 1 end");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);

    const exp = program.block.items[0];
    try testing.expectEqualStrings(exp.func.sym.?.symbol.lexeme, "add-1");
    try testing.expectEqualStrings(exp.func.args.items[0].symbol.lexeme, "y");
    const binexp = exp.func.body.block.items[0];
    try testing.expectEqualStrings(binexp.binexp.a.symbol.lexeme, "y");
    try testing.expectEqualStrings(binexp.binexp.op.symbol.lexeme, "+");
    try testing.expectEqual(binexp.binexp.b.number.num, 1);
}
