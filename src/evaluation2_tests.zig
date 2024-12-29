const std = @import("std");
const r = @import("reader2.zig");
const v = @import("values.zig");
const e = @import("evaluation2.zig");
const expect = std.testing.expect;
const expectEq = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqStr = std.testing.expectEqualStrings;
const gc = @import("gc.zig");

const allocator = std.heap.page_allocator;

fn evalStr(code: []const u8) *v.Value {
    var g = gc.Gc.init(allocator);
    var ev = e.Eval.init(&g);
    return ev.eval(code) catch unreachable;
}

test "evaluating numbers" {
    const num = evalStr("1 2 3");
    try expectEq(3.0, num.number);
}

test "evaluating symbols" {
    var g = gc.Gc.init(allocator);
    try g.env().set("hello", g.num(123.0));
    var ev = e.Eval.init(&g);
    const value = try ev.eval("hello");
    try expectEq(123.0, value.number);

    const err = ev.eval("world");
    try expectError(error.UndefinedSymbol, err);
    const log: []const u8 = try ev.getErrorLog();
    try expectEqStr("Undefined symbol 'world'", log);
}

test "evaluating binary expressions" {
    var g = gc.Gc.init(allocator);
    var ev = e.Eval.init(&g);

    try expectEq(3, (try ev.eval("1 + 3 + -1")).number);
    try expectEq(12, (try ev.eval("3 * 4")).number);
    try expectEq(8 - 5, (try ev.eval("8 - 5")).number);
    try expectEq(1.0 / 3.0, (try ev.eval("1 / 3")).number);
}

test "evaluating unary expressions" {
    var g = gc.Gc.init(allocator);
    var ev = e.Eval.init(&g);

    try expectEq(-3, (try ev.eval("-3")).number);
    try expectEq(true, (try ev.eval("not false")).boolean);
    try expectEq(1, (try ev.eval("not 0")).number);
}

test "evaluating definition" {
    var g = gc.Gc.init(allocator);
    var ev = e.Eval.init(&g);

    const value = try ev.eval(
        \\ a := 9
        \\ a
    );
    try expectEq(9, value.number);
}

test "evaluate defining and calling functions" {
    var g = gc.Gc.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(
        \\ fun a(b) b + 1 end
        \\ a(9)
    );
    try expectEq(10, value.number);
}

test "evaluating anonymous functions" {
    var g = gc.Gc.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(
        \\ a := fun(b) b + 1 end
        \\ a(9)
    );
    try expectEq(10, value.number);
    const value2 = try ev.eval(
        \\ b := fn(b) b + 1
        \\ b(4)
    );
    try expectEq(5, value2.number);
}

test "evaluating if expressions" {
    var g = gc.Gc.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval("if true then 1 else 2 end");
    try expectEq(1, value.number);
    const value2 = try ev.eval("if false then 1 else 2 end");
    try expectEq(2, value2.number);
}

test "evaluating recursive functions" {
    var g = gc.Gc.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(
        \\fun factorial(n)
        \\  if n < 2 then
        \\    1
        \\  else
        \\    n * factorial(n - 1)
        \\  end
        \\end
        \\factorial(5)
    );
    try expectEq(120, value.number);
}

// test "evaluating functions out of order" {
//     var g = gc.Gc.init(allocator);
//     var ev = e.Eval.init(&g);
// }
