const std = @import("std");
const expect = std.testing.expect;
const expectEq = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqStr = std.testing.expectEqualStrings;
const allocator = std.heap.page_allocator;

const e = @import("evaluation.zig");
const gc = @import("gc.zig");
const r = @import("reader.zig");
const v = @import("values.zig");

fn evalStr(code: []const u8) *v.Value {
    var g = gc.Gc.init(allocator);
    const env = v.Environment.init(allocator) catch unreachable;
    var ev = e.Eval.init(&g);
    return ev.eval(env, code) catch unreachable;
}

test "evaluating numbers" {
    const num = evalStr("1 2 3");
    try expectEq(3.0, num.number);
}

test "evaluating symbols" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    try env.define("hello", g.num(123.0));
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env, "hello");
    try expectEq(123.0, value.number);

    const err = ev.eval(env, "world");
    try expectError(error.UndefinedSymbol, err);
}

test "evaluating binary expressions" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);

    try expectEq(3, (try ev.eval(env, "1 + 3 + -1")).number);
    try expectEq(12, (try ev.eval(env, "3 * 4")).number);
    try expectEq(8 - 5, (try ev.eval(env, "8 - 5")).number);
    try expectEq(1.0 / 3.0, (try ev.eval(env, "1 / 3")).number);
}

test "evaluating unary expressions" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);

    try expectEq(-3, (try ev.eval(env, "-3")).number);
    try expectEq(true, (try ev.eval(env, "not false")).boolean);
    try expectEq(1, (try ev.eval(env, "not 0")).number);
}

test "evaluating definition" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);

    const value = try ev.eval(env,
        \\ a := 9
        \\ a
    );
    try expectEq(9, value.number);
}

test "evaluate defining and calling functions" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
        \\ fun a(b) b + 1 end
        \\ a(9)
    );
    try expectEq(10, value.number);
}

test "evaluating anonymous functions" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
        \\ a := fun(b) b + 1 end
        \\ a(9)
    );
    try expectEq(10, value.number);
    const value2 = try ev.eval(env,
        \\ b := fn(b) b + 1
        \\ b(4)
    );
    try expectEq(5, value2.number);
}

test "evaluating if expressions" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env, "if true then 1 else 2 end");
    try expectEq(1, value.number);
    const value2 = try ev.eval(env, "if false then 1 else 2 end");
    try expectEq(2, value2.number);
}

test "evaluating recursive functions" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
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

test "evaluating functions out of order" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
        \\fun a() b() end
        \\fun b() 69 end
        \\a()
    );
    try expectEq(69, value.number);
}

test "evaluating passing functions" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
        \\fun a(b) b() end
        \\fun b() 69 end
        \\a(b)
    );
    try expectEq(69, value.number);
}

test "closures and scoping" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = ev.eval(env,
        \\ add := fn(a) fn(b) a + b
        \\ add(2)(3)
        \\ a + b
    );
    try std.testing.expectError(error.UndefinedSymbol, value);
    const value2 = try ev.eval(env,
        \\ add := fn(a) fn(b) a + b
        \\ add(2)(3)
    );
    try expectEq(5, value2.number);
}

test "records and dot syntax" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
        \\ x := { y: { z: 123 } }
        \\ x.y.z
    );
    try expectEq(123, value.number);
    const value2 = try ev.eval(env,
        \\ x := { y: fn() { z: 123 } }
        \\ x.y().z
    );
    try expectEq(123, value2.number);
}

test "assignment" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
        \\ x := 0
        \\ x = 6
        \\ x
    );
    try expectEq(6, value.number);
}

test "table assignment" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
        \\ x := { y: 0 }
        \\ x.y = 6
    );
    try expectEq(6, value.number);
}

test "assignment and scoping" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
        \\ x := 0
        \\ do x = 3 end
        \\ x
    );
    try expectEq(3, value.number);
}

test "assignment and out of scoping" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env,
        \\ x := 0
        \\ do x := 3 end
        \\ x
    );
    try expectEq(0, value.number);
}

test "parenthesis expression" {
    var g = gc.Gc.init(allocator);
    const env = try v.Environment.init(allocator);
    var ev = e.Eval.init(&g);
    const value = try ev.eval(env, "(11 + 1)");
    try expectEq(12, value.number);
}
