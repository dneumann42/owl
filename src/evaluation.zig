// works directly on the ast

const v = @import("values.zig");
const r = @import("reader.zig");
const g = @import("gc.zig");
const ast = @import("ast.zig");
const std = @import("std");
// const pretty = @import("pretty");
const assert = std.debug.assert;
const nothing = v.nothing;

pub const EvalError = error{ KeyNotFound, OutOfMemory, NotImplemented, ReaderError, UndefinedSymbol, InvalidUnexp, ValueError, InvalidFunction, InvalidCallable, InvalidBinexp, InvalidLExpr, InvalidAssignment };

pub const Eval = struct {
    allocator: std.mem.Allocator,
    error_log: std.ArrayList([]const u8),
    function_bodies: std.ArrayList(*ast.Ast),

    pub fn init(allocator: std.mem.Allocator) Eval {
        return Eval{
            .allocator = allocator,
            .error_log = std.ArrayList([]const u8).init(allocator), //
            .function_bodies = std.ArrayList(*ast.Ast).init(allocator),
        };
    }

    pub fn deinit(self: *Eval) void {
        self.error_log.deinit();
    }

    pub fn addFunctionBody(self: *Eval, body: *ast.Ast) error{OutOfMemory}!usize {
        try self.function_bodies.append(body);
        return self.function_bodies.items.len - 1;
    }

    pub fn logErr(self: *Eval, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.allocator, fmt, args) catch unreachable;
        self.error_log.append(msg) catch unreachable;
    }

    pub fn getErrorLog(self: *Eval) []const u8 {
        return std.mem.join(self.allocator, "\n", self.error_log.items) catch "Failed to allocate log";
    }

    pub fn clearErrorLog(self: *Eval) void {
        self.error_log.clearAndFree();
    }

    pub fn eval(self: *Eval, gc: *g.Gc, code: []const u8) EvalError!*v.Value {
        var reader = r.Reader.init(gc.allocator, code) catch {
            return error.ReaderError;
        };
        const node = switch (reader.read()) {
            .success => |n| n,
            .failure => {
                return error.ReaderError;
            },
        };

        return self.evalNode(gc, node);
    }

    pub fn evalNode(self: *Eval, gc: *g.Gc, node: *ast.Ast) EvalError!*v.Value {
        return switch (node.*) {
            .number, .boolean, .string => self.evalLiteral(gc, node),
            .dictionary => |d| self.evalDictionary(gc, d),
            .symbol => |s| self.evalSymbol(gc, s),
            .definition => |define| self.evalDefinition(gc, define),
            .assignment => |assign| self.evalAssignment(gc, assign),
            .block => |xs| self.evalBlock(gc, xs),
            .binexp => |bin| self.evalBinexp(gc, bin),
            .unexp => |un| self.evalUnexp(gc, un),
            .func => |fun| self.evalFunc(gc, fun),
            .call => |call| self.evalCall(gc, call),
            .dot => |dot| self.evalDot(gc, dot),
            .ifx => |ifx| self.evalIf(gc, ifx),
            .whilex => |whilex| self.evalWhile(gc, whilex),
            .forx => |whilex| self.evalFor(gc, whilex),
            .list => |xs| return self.evalList(gc, xs),
        };
    }

    pub fn evalBlock(self: *Eval, gc: *g.Gc, xs: std.ArrayList(*ast.Ast)) EvalError!*v.Value {
        var value: *v.Value = gc.nothing();
        var new_gc = gc.push();
        for (xs.items) |node| {
            value = try self.evalNode(&new_gc, node);
        }
        return value;
    }

    pub fn evalBinexp(self: *Eval, gc: *g.Gc, bin: ast.Binexp) EvalError!*v.Value {
        const left = try self.evalNode(gc, bin.a);
        const right = try self.evalNode(gc, bin.b);
        return if (std.mem.eql(u8, bin.op.symbol, "+"))
            gc.num(left.toNumber() + right.toNumber())
        else if (std.mem.eql(u8, bin.op.symbol, "-"))
            gc.num(left.toNumber() - right.toNumber())
        else if (std.mem.eql(u8, bin.op.symbol, "*"))
            gc.num(left.toNumber() * right.toNumber())
        else if (std.mem.eql(u8, bin.op.symbol, "/"))
            gc.num(left.toNumber() / right.toNumber())
        else if (std.mem.eql(u8, bin.op.symbol, "<"))
            gc.boolean(left.toNumber() < right.toNumber())
        else if (std.mem.eql(u8, bin.op.symbol, ">"))
            gc.boolean(left.toNumber() > right.toNumber())
        else if (std.mem.eql(u8, bin.op.symbol, "eq"))
            gc.boolean(left.isEql(right))
        else {
            self.logErr("Unexpected binary operator '{s}'", .{bin.op.symbol});
            return error.InvalidBinexp;
        };
    }

    pub fn evalUnexp(self: *Eval, gc: *g.Gc, un: ast.Unexp) EvalError!*v.Value {
        _ = self;
        if (std.mem.eql(u8, un.op.symbol, "-")) {
            return gc.num(-un.value.number);
        }
        if (std.mem.eql(u8, un.op.symbol, "not")) {
            switch (un.value.*) {
                .number => |n| {
                    return if (n == 0) gc.num(1) else gc.num(0);
                },
                .boolean => |b| {
                    return gc.boolean(!b);
                },
                else => {
                    return error.InvalidUnexp;
                },
            }
        }
        return error.InvalidUnexp;
    }

    pub fn evalDefinition(self: *Eval, gc: *g.Gc, define: ast.Define) EvalError!*v.Value {
        const sym = define.left.symbol;
        const value = try self.evalNode(gc, define.right);
        try gc.env().define(sym, value);
        return value;
    }

    pub fn evalLiteral(self: *Eval, gc: *g.Gc, node: *ast.Ast) EvalError!*v.Value {
        _ = self;
        return switch (node.*) {
            .number => |n| gc.num(n),
            .string => |s| gc.str(s),
            .boolean => |b| gc.boolean(b),
            else => gc.nothing(),
        };
    }

    pub fn evalDictionary(self: *Eval, gc: *g.Gc, d: ast.Dictionary) EvalError!*v.Value {
        var dict = v.Dictionary.init(gc.allocator);
        for (d.items) |kv| {
            const key = gc.sym(kv.key.symbol);
            const value = try self.evalNode(gc, kv.value);
            try dict.put(key, value);
        }
        return gc.create(.{ .dictionary = dict });
    }

    pub fn evalSymbol(self: *Eval, gc: *g.Gc, s: []const u8) EvalError!*v.Value {
        if (std.mem.eql(u8, s, "nothing")) {
            return gc.nothing();
        }
        if (gc.env().find(s)) |value| {
            return value;
        }
        self.logErr("Undefined symbol '{s}'", .{s});
        return error.UndefinedSymbol;
    }

    pub fn reduceLExpr(self: *Eval, gc: *g.Gc, dot: ast.Dot) EvalError!*v.Value {
        switch (dot.a.*) {
            .symbol => |s| {
                return gc.env().find(s) orelse gc.nothing();
            },
            .dot => |d| {
                const dict = try self.reduceLExpr(gc, d);
                const key = gc.sym(d.b.symbol);
                return dict.dictionary.get(key) orelse gc.nothing();
            },
            .call => |c| {
                return self.evalCall(gc, c);
            },
            else => {
                return gc.nothing();
            },
        }
    }

    pub fn evalAssignment(self: *Eval, gc: *g.Gc, assign: ast.Assign) EvalError!*v.Value {
        switch (assign.left.*) {
            .dot => |dot| {
                var dict = try self.reduceLExpr(gc, dot);
                const key = gc.sym(dot.b.symbol);
                const value = try self.evalNode(gc, assign.right);
                try dict.dictionary.put(key, value);
                return value;
            },
            .symbol => |key| {
                const value = try self.evalNode(gc, assign.right);
                try gc.env().set(key, value);
                return value;
            },
            else => {
                return error.InvalidAssignment;
            },
        }
    }

    pub fn evalFunc(self: *Eval, gc: *g.Gc, fun: ast.Func) EvalError!*v.Value {
        var fs = std.ArrayList([]const u8).init(gc.allocator);
        for (fun.args.items) |arg| {
            fs.append(arg.symbol) catch {
                return error.OutOfMemory;
            };
        }
        const new_environment = v.Environment.init(gc.allocator) catch unreachable;
        new_environment.next = gc.env();

        const address = try self.addFunctionBody(fun.body);
        const func = gc.create(.{ .function = v.Function.init(address, fs, new_environment) }) catch {
            return error.OutOfMemory;
        };

        if (fun.sym) |symbol| {
            try gc.env().set(symbol.symbol, func);
        }

        return func;
    }

    pub fn evalList(self: *Eval, gc: *g.Gc, xs: std.ArrayList(*ast.Ast)) EvalError!*v.Value {
        var list = std.ArrayList(*v.Value).init(gc.allocator);
        for (xs.items) |item| {
            const value = try self.evalNode(gc, item);
            try list.append(value);
        }
        return gc.create(.{ .list = list });
    }

    pub fn evalCall(self: *Eval, gc: *g.Gc, call: ast.Call) EvalError!*v.Value {
        switch (call.callable.*) {
            .symbol => |s| {
                if (std.mem.eql(u8, s, "eval")) {
                    const str = try self.evalNode(gc, call.args.items[0]);
                    switch (str.*) {
                        .string => {},
                        else => {
                            return error.InvalidCallable;
                        },
                    }
                    return self.eval(gc, str.string) catch |e| {
                        const log = self.getErrorLog();
                        self.clearErrorLog();
                        std.log.err("{any} {s}", .{ e, log });
                        return gc.nothing();
                    };
                } else if (std.mem.eql(u8, s, "cons")) {
                    const a = try self.evalNode(gc, call.args.items[0]);
                    const b = try self.evalNode(gc, call.args.items[1]);
                    return v.cons(gc, a, b);
                }
            },
            else => {},
        }

        const fun = switch ((try self.evalNode(gc, call.callable)).*) {
            .function => |fun| fun,
            .nativeFunction => |nfun| {
                return self.evalNativeCallFn(gc, nfun, call.args);
            },
            else => {
                return error.InvalidCallable;
            },
        };
        const body = self.function_bodies.items[fun.address];
        var next = gc.pushEnv(fun.env);
        for (0..fun.params.items.len) |i| {
            const param = fun.params.items[i];
            const value = try self.evalNode(gc, call.args.items[i]);
            try next.env().set(param, value);
        }
        return self.evalNode(&next, body);
    }

    pub fn evalNativeCallFn(self: *Eval, gc: *g.Gc, native: v.NativeFunction, args: std.ArrayList(*ast.Ast)) EvalError!*v.Value {
        var vs = std.ArrayList(*v.Value).init(gc.allocator);
        for (args.items) |arg| {
            try vs.append(try self.evalNode(gc, arg));
        }

        return native(gc, vs);
    }

    pub fn evalDot(self: *Eval, gc: *g.Gc, dot: ast.Dot) EvalError!*v.Value {
        const a = try self.evalNode(gc, dot.a);
        const b = gc.sym(dot.b.symbol);

        switch (a.*) {
            .dictionary => |d| {
                return d.get(b) orelse gc.nothing();
            },
            else => {
                return error.NotImplemented;
            },
        }
    }

    pub fn evalIf(self: *Eval, gc: *g.Gc, ifx: ast.If) EvalError!*v.Value {
        for (ifx.branches.items) |branch| {
            const cond = try self.evalNode(gc, branch.check);
            if (cond.isTrue()) {
                return self.evalNode(gc, branch.then);
            }
        }

        if (ifx.elseBranch) |elseBranch| {
            return self.evalNode(gc, elseBranch);
        }

        return gc.nothing();
    }

    pub fn evalWhile(self: *Eval, gc: *g.Gc, whilex: ast.While) EvalError!*v.Value {
        var result = gc.nothing();
        while (true) {
            const condition_result = try self.evalNode(gc, whilex.condition);
            if (condition_result.isFalse()) {
                break;
            }
            result = try self.evalNode(gc, whilex.block);
        }
        return result;
    }

    pub fn evalFor(self: *Eval, gc: *g.Gc, ifx: ast.For) EvalError!*v.Value {
        // rewrites into a while loop
        // TODO: move this to a preprocessor step

        // do
        //   next = range(0, 10)
        //   i = next()
        //   while i do
        //     ;; block
        //     i = next()
        //   end
        // end

        const iter_sym = try ast.sym(gc.allocator, "next");
        const iter_call = try ast.call(gc.allocator, iter_sym, std.ArrayList(*ast.Ast).init(gc.allocator));
        var body = std.ArrayList(*ast.Ast).init(gc.allocator);
        try body.append(try ast.define(gc.allocator, iter_sym, ifx.iterable));
        try body.append(try ast.define(gc.allocator, ifx.variable, iter_call));

        const condition = ifx.variable;
        var while_body = ifx.block.block;
        try while_body.append(try ast.assign(gc.allocator, ifx.variable, iter_call));

        const whilex = try ast.whilex(gc.allocator, condition, try ast.block(gc.allocator, while_body));
        try body.append(whilex);

        return self.evalNode(gc, try ast.block(gc.allocator, body));
    }
};
