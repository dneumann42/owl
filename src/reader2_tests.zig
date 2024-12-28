const r = @import("reader2.zig");
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
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.block.items[0].number, 1.0);
}

test "reading number literals" {
    var reader = try r.Reader.init(testing.allocator, "31415926 1 2 3");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.block.items[0].number, 31415926);
    try testing.expectEqual(program.block.items[1].number, 1);
    try testing.expectEqual(program.block.items[2].number, 2);
    try testing.expectEqual(program.block.items[3].number, 3);
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
    try testing.expectEqualStrings(aa.unexp.op.symbol, "-");
    try testing.expectEqual(aa.unexp.value.number, 123);
}

test "reading binary expressions" {
    var reader = try r.Reader.init(testing.allocator, "1 or 2 and 3 4 + 5");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];
    try testing.expectEqual(exp.binexp.a.number, 1);
    try testing.expectEqualStrings(exp.binexp.op.symbol, "or");
    try testing.expectEqual(exp.binexp.b.binexp.a.number, 2);
    try testing.expectEqualStrings(exp.binexp.b.binexp.op.symbol, "and");
    try testing.expectEqual(exp.binexp.b.binexp.b.number, 3);

    const exp2 = program.block.items[1];
    try testing.expectEqual(exp2.binexp.a.number, 4);
    try testing.expectEqual(exp2.binexp.b.number, 5);
}

test "reading function calls" {
    var reader = try r.Reader.init(testing.allocator, "call(1, 2)");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);

    const exp = program.block.items[0];
    try testing.expectEqualStrings(exp.call.callable.symbol, "call");
    try testing.expectEqual(exp.call.args.items[0].number, 1);
    try testing.expectEqual(exp.call.args.items[1].number, 2);
}

test "reading dot & call expressions" {
    var reader = try r.Reader.init(testing.allocator, "a.b a().b a.b() a.b().c");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);

    const exp1 = program.block.items[0];
    try testing.expectEqualStrings(exp1.dot.a.symbol, "a");
    try testing.expectEqualStrings(exp1.dot.b.symbol, "b");

    const exp2 = program.block.items[1];
    try testing.expectEqualStrings(exp2.dot.a.call.callable.symbol, "a");
    try testing.expectEqualStrings(exp2.dot.b.symbol, "b");

    const exp3 = program.block.items[2];
    try testing.expectEqualStrings(exp3.call.callable.dot.a.symbol, "a");
    try testing.expectEqualStrings(exp3.call.callable.dot.b.symbol, "b");

    const exp4 = program.block.items[3];
    // try testing.expectEqualStrings(exp4.dot.a.symbol, "a");
    // try testing.expectEqualStrings(exp4.call.callable.dot.b.symbol, "b");
    try testing.expectEqualStrings(exp4.dot.b.symbol, "c");
}

test "reading function definitions" {
    var reader = try r.Reader.init(testing.allocator, "fun add-1(y) y + 1 end");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];

    try testing.expectEqualStrings(exp.func.sym.?.symbol, "add-1");
    try testing.expectEqualStrings(exp.func.args.items[0].symbol, "y");
    const binexp = exp.func.body.block.items[0];
    try testing.expectEqualStrings(binexp.binexp.a.symbol, "y");
    try testing.expectEqualStrings(binexp.binexp.op.symbol, "+");
    try testing.expectEqual(binexp.binexp.b.number, 1);
}

test "reading lambdas" {
    var reader = try r.Reader.init(testing.allocator, "fn(y) y + 1");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];

    try testing.expectEqual(exp.func.sym, null);
    try testing.expectEqualStrings(exp.func.args.items[0].symbol, "y");
    const binexp = exp.func.body;
    try testing.expectEqualStrings(binexp.binexp.a.symbol, "y");
    try testing.expectEqualStrings(binexp.binexp.op.symbol, "+");
    try testing.expectEqual(binexp.binexp.b.number, 1);
}

test "reading definitions" {
    var reader = try r.Reader.init(testing.allocator, "x := 10");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];
    try testing.expectEqualStrings(exp.definition.left.symbol, "x");
    try testing.expectEqual(exp.definition.right.number, 10);
}

test "reading assignment" {
    var reader = try r.Reader.init(testing.allocator, "x = 10");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];
    try testing.expectEqualStrings(exp.assignment.left.symbol, "x");
    try testing.expectEqual(exp.assignment.right.number, 10);
}

test "reading do blocks" {
    var reader = try r.Reader.init(testing.allocator, "do 1 end");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];
    try testing.expect(exp.block.items.len == 1);
}

test "reading if" {
    var reader = try r.Reader.init(testing.allocator, "if true then 1 end");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];

    try testing.expectEqual(exp.ifx.elseBranch, null);
    try testing.expectEqual(exp.ifx.branches.items.len, 1);
    try testing.expectEqual(exp.ifx.branches.items[0].check.boolean, true);
    try testing.expectEqual(exp.ifx.branches.items[0].then.block.items[0].number, 1);
}

test "reading if with else" {
    var reader = try r.Reader.init(testing.allocator, "if true then 1 else 2 end");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];
    try testing.expectEqual(exp.ifx.elseBranch.?.block.items[0].number, 2);
    try testing.expectEqual(exp.ifx.branches.items.len, 1);
    try testing.expectEqual(exp.ifx.branches.items[0].check.boolean, true);
    try testing.expectEqual(exp.ifx.branches.items[0].then.block.items[0].number, 1);
}

test "reading if with elif and else" {
    var reader = try r.Reader.init(testing.allocator, "if true then 1 elif false then 3 else 2 end");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];
    try testing.expectEqual(exp.ifx.elseBranch.?.block.items[0].number, 2);
    try testing.expectEqual(exp.ifx.branches.items.len, 2);
    try testing.expectEqual(exp.ifx.branches.items[0].check.boolean, true);
    try testing.expectEqual(exp.ifx.branches.items[0].then.block.items[0].number, 1);
    try testing.expectEqual(exp.ifx.branches.items[1].check.boolean, false);
    try testing.expectEqual(exp.ifx.branches.items[1].then.block.items[0].number, 3);
}

test "reading conditions" {
    var reader = try r.Reader.init(testing.allocator,
        \\cond
        \\  1 + 1 do 2 end
        \\  2     do 3 end
        \\end
    );
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];

    try testing.expectEqual(exp.ifx.elseBranch, null);
    try testing.expectEqual(exp.ifx.branches.items.len, 2);
    try testing.expectEqual(exp.ifx.branches.items[0].check.binexp.a.number, 1);
    try testing.expectEqual(exp.ifx.branches.items[0].then.block.items[0].number, 2);
}

test "reading dictionary literals" {
    var reader = try r.Reader.init(testing.allocator, "{ a: 1 b: 2 }");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];

    try testing.expectEqual(exp.dictionary.items.len, 2);
    try testing.expectEqualStrings(exp.dictionary.items[0].key.symbol, "a");
    try testing.expectEqual(exp.dictionary.items[0].value.number, 1);
    try testing.expectEqualStrings(exp.dictionary.items[1].key.symbol, "b");
    try testing.expectEqual(exp.dictionary.items[1].value.number, 2);
}

test "reading list literals" {
    var reader = try r.Reader.init(testing.allocator, "[1 2 3]");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];

    try testing.expectEqual(exp.list.items[0].number, 1);
    try testing.expectEqual(exp.list.items[1].number, 2);
    try testing.expectEqual(exp.list.items[2].number, 3);
}

test "reading empty list literals" {
    var reader = try r.Reader.init(testing.allocator, "[]");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];

    try testing.expectEqual(exp.list.items.len, 0);
}

test "blocks" {
    var reader = try r.Reader.init(testing.allocator, "1 2 3");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    try testing.expectEqual(program.block.items[0].number, 1);
    try testing.expectEqual(program.block.items[1].number, 2);
    try testing.expectEqual(program.block.items[2].number, 3);
}

test "building function value from ast" {
    var reader = try r.Reader.init(testing.allocator, "fun id(a) a end");
    defer reader.deinit();
    const program = reader.read().success;
    defer a.deinit(program, reader.allocator);
    const exp = program.block.items[0];
    var G = g.Gc.init(testing.allocator);
    defer G.deinit();
    const value = try a.buildValueFromAst(&G, exp);
    try testing.expectEqualStrings("fun", value.cons.car.?.symbol);
    try testing.expectEqualStrings("id", value.cons.cdr.?.cons.car.?.symbol);
    try testing.expectEqualStrings("a", value.cons.cdr.?.cons.cdr.?.cons.car.?.cons.car.?.symbol);
}
