// works directly on the ast

const std = @import("std");
const assert = std.debug.assert;

const ast = @import("ast.zig");
const g = @import("gc.zig");
const r = @import("reader.zig");
const v = @import("values.zig");
const nothing = v.nothing;

pub const EvalError = error{ KeyNotFound, OutOfMemory, NotImplemented, ReaderError, UndefinedSymbol, InvalidUnexp, ValueError, InvalidFunction, InvalidCallable, InvalidBinexp, InvalidLExpr, InvalidAssignment, Undefined, InvalidDotValue };

pub const EvalErrorReport = struct {
    message: []const u8,
    line: usize,
};

pub const Eval = struct {
    gc: *g.Gc,
    error_log: std.ArrayList(EvalErrorReport),
    function_bodies: std.ArrayList(*ast.Ast),
    environments: std.ArrayList(*v.Environment),

    pub fn init(gc: *g.Gc) Eval {
        return Eval{
            .gc = gc,
            .error_log = std.ArrayList(EvalErrorReport).init(gc.allocator), //
            .function_bodies = std.ArrayList(*ast.Ast).init(gc.allocator),
            .environments = std.ArrayList(*v.Environment).init(gc.allocator),
        };
    }

    pub fn deinit(self: *Eval, ast_allocator: std.mem.Allocator) void {
        for (self.error_log.items) |log| {
            self.gc.allocator.free(log.message);
        }
        self.error_log.deinit();
        for (self.function_bodies.items) |item| {
            ast.deinit(item, ast_allocator);
        }
        self.function_bodies.deinit();
        for (self.environments.items) |env| {
            env.deinit();
        }
        self.environments.deinit();
    }

    pub fn push(self: *Eval, env: *v.Environment) !*v.Environment {
        const new_env = env.push();
        try self.environments.append(new_env);
        return new_env;
    }

    pub fn addFunctionBody(self: *Eval, body: *ast.Ast) error{OutOfMemory}!usize {
        try self.function_bodies.append(body);
        return self.function_bodies.items.len - 1;
    }

    pub fn logErr(self: *Eval, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.gc.allocator, fmt, args) catch unreachable;
        self.error_log.append(EvalErrorReport{ .message = msg, .line = 0 }) catch unreachable;
    }

    pub fn logErrLn(self: *Eval, line: usize, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.gc.allocator, fmt, args) catch unreachable;
        self.error_log.append(EvalErrorReport{ .message = msg, .line = line }) catch unreachable;
    }

    pub fn clearErrorLog(self: *Eval) void {
        self.error_log.clearAndFree();
    }

    pub fn eval(self: *Eval, env: *v.Environment, code: []const u8) EvalError!*v.Value {
        var reader = r.Reader.init(self.gc.allocator, code) catch {
            return error.ReaderError;
        };
        const node = switch (reader.read()) {
            .ok => |n| n,
            .err => {
                return error.ReaderError;
            },
        };

        return self.evalAst(env, node);
    }

    pub fn evalAst(self: *Eval, env: *v.Environment, a: *ast.Ast) EvalError!*v.Value {
        return switch (a.*.node) {
            .number, .boolean, .string => self.evalLiteral(env, a),
            .dictionary => |d| self.evalDictionary(env, d),
            .symbol => self.evalSymbol(env, a),
            .definition => |define| self.evalDefinition(env, define),
            .assignment => |assign| self.evalAssignment(env, assign),
            .block => |xs| self.evalBlock(env, xs),
            .binexp => |bin| self.evalBinexp(env, bin),
            .unexp => |un| self.evalUnexp(env, un),
            .func => |fun| self.evalFunc(env, fun),
            .call => |call| self.evalCall(env, call),
            .dot => |dot| self.evalDot(env, dot),
            .ifx => |ifx| self.evalIf(env, ifx),
            .whilex => |whilex| self.evalWhile(env, whilex),
            .forx => |forx| self.evalFor(env, forx),
            .list => |xs| return self.evalList(env, xs),
            .use => return self.gc.nothing(),
        };
    }

    pub fn evalBlock(self: *Eval, env: *v.Environment, xs: std.ArrayList(*ast.Ast)) EvalError!*v.Value {
        var value: *v.Value = self.gc.nothing();
        const new_env = try self.push(env);
        for (xs.items) |node| {
            value = try self.evalAst(new_env, node);
        }
        return value;
    }

    pub fn evalBinexp(self: *Eval, env: *v.Environment, bin: ast.Binexp) EvalError!*v.Value {
        const left = try self.evalAst(env, bin.a);
        const right = try self.evalAst(env, bin.b);
        return if (std.mem.eql(u8, bin.op.node.symbol, "+"))
            self.gc.num(v.toNumber(left) + v.toNumber(right))
        else if (std.mem.eql(u8, bin.op.node.symbol, "-"))
            self.gc.num(v.toNumber(left) - v.toNumber(right))
        else if (std.mem.eql(u8, bin.op.node.symbol, "*"))
            self.gc.num(v.toNumber(left) * v.toNumber(right))
        else if (std.mem.eql(u8, bin.op.node.symbol, "/"))
            self.gc.num(v.toNumber(left) / v.toNumber(right))
        else if (std.mem.eql(u8, bin.op.node.symbol, "<"))
            self.gc.boolean(v.toNumber(left) < v.toNumber(right))
        else if (std.mem.eql(u8, bin.op.node.symbol, ">"))
            self.gc.boolean(v.toNumber(left) > v.toNumber(right))
        else if (std.mem.eql(u8, bin.op.node.symbol, "eq"))
            self.gc.boolean(v.isEql(left, right))
        else {
            self.logErrLn(bin.op.meta.line, "Unexpected binary operator '{s}'", .{bin.op.node.symbol});
            return error.InvalidBinexp;
        };
    }

    pub fn evalUnexp(self: *Eval, env: *v.Environment, un: ast.Unexp) EvalError!*v.Value {
        if (std.mem.eql(u8, un.op.node.symbol, "-")) {
            return self.gc.num(-un.value.node.number);
        }
        if (std.mem.eql(u8, un.op.node.symbol, "not")) {
            const value = try self.evalAst(env, un.value);
            switch (value.*) {
                .number => |n| {
                    return if (n == 0) self.gc.num(1) else self.gc.num(0);
                },
                .boolean => |b| {
                    return self.gc.boolean(!b);
                },
                else => {
                    return error.InvalidUnexp;
                },
            }
        }
        self.logErr("Invalid unary operator '{s}'", .{un.op.node.symbol});
        return error.InvalidUnexp;
    }

    pub fn evalDefinition(self: *Eval, env: *v.Environment, define: ast.Pair) EvalError!*v.Value {
        const sym = define.a.node.symbol;
        const value = try self.evalAst(env, define.b);
        try env.define(sym, value);
        return value;
    }

    pub fn evalLiteral(self: *Eval, env: *v.Environment, lit: *ast.Ast) EvalError!*v.Value {
        _ = env;
        return switch (lit.node) {
            .number => |n| self.gc.num(n),
            .boolean => |b| self.gc.boolean(b),
            .string => |s| self.gc.strAlloc(s),
            else => self.gc.nothing(),
        };
    }

    pub fn evalDictionary(self: *Eval, env: *v.Environment, d: ast.Dictionary) EvalError!*v.Value {
        // TODO: fix double free, we need to transfer ownership of symbol and dealloc the ast
        var dict = v.Dictionary.init(self.gc.allocator);
        for (d.items) |kv| {
            const key = self.gc.symAlloc(kv.a.node.symbol);
            const value = try self.evalAst(env, kv.b);
            try dict.put(key, value);
        }
        return self.gc.create(.{ .dictionary = dict });
    }

    pub fn evalSymbol(self: *Eval, env: *v.Environment, s: *ast.Ast) EvalError!*v.Value {
        if (std.mem.eql(u8, s.node.symbol, "nothing")) {
            return self.gc.nothing();
        }
        if (env.find(s.node.symbol)) |value| {
            return value;
        }
        self.logErrLn(s.meta.line, "Undefined symbol '{s}'", .{s.node.symbol});
        return error.UndefinedSymbol;
    }

    pub fn reduceLExpr(self: *Eval, env: *v.Environment, dot: ast.Pair) EvalError!*v.Value {
        switch (dot.a.*.node) {
            .symbol => |s| {
                return env.find(s) orelse self.gc.nothing();
            },
            .dot => |d| {
                const dict = try self.reduceLExpr(env, d);
                const key = self.gc.symAlloc(d.b.node.symbol);
                return dict.dictionary.get(key) orelse self.gc.nothing();
            },
            .call => |c| {
                return self.evalCall(env, c);
            },
            else => {
                return self.gc.nothing();
            },
        }
    }

    pub fn evalAssignment(self: *Eval, env: *v.Environment, assign: ast.Pair) EvalError!*v.Value {
        switch (assign.a.*.node) {
            .dot => |dot| {
                var dict = try self.reduceLExpr(env, dot);
                const key = self.gc.symAlloc(dot.b.node.symbol);
                const value = try self.evalAst(env, assign.b);
                try dict.dictionary.put(key, value);
                return value;
            },
            .symbol => |key| {
                const value = try self.evalAst(env, assign.b);
                env.set(key, value) catch |e| switch (e) {
                    error.KeyNotFound => {
                        self.logErrLn(assign.a.meta.line, "Variable is undefined '{s}'", .{key});
                        return e;
                    },
                    else => return e,
                };
                return value;
            },
            else => {
                return error.InvalidAssignment;
            },
        }
    }

    pub fn evalFunc(self: *Eval, env: *v.Environment, fun: ast.Func) EvalError!*v.Value {
        var fs = std.ArrayList([]const u8).init(self.gc.allocator);
        for (fun.args.items) |arg| {
            fs.append(arg.node.symbol) catch {
                return error.OutOfMemory;
            };
        }

        const address = try self.addFunctionBody(fun.body);
        const new_env = try self.push(env);

        const func = self.gc.create(.{ .function = v.Function.init(address, fs, new_env) }) catch {
            return error.OutOfMemory;
        };
        if (fun.sym) |symbol| {
            try env.define(symbol.node.symbol, func);
        }
        return func;
    }

    pub fn evalList(self: *Eval, env: *v.Environment, xs: std.ArrayList(*ast.Ast)) EvalError!*v.Value {
        var list = std.ArrayList(*v.Value).init(self.gc.allocator);
        for (xs.items) |item| {
            const value = try self.evalAst(env, item);
            try list.append(value);
        }
        return v.clist(self.gc, list);
    }

    pub fn evalCall(self: *Eval, env: *v.Environment, call: ast.Call) EvalError!*v.Value {
        switch (call.callable.*.node) {
            .symbol => |s| {
                if (std.mem.eql(u8, s, "eval")) {
                    const str = try self.evalAst(env, call.args.items[0]);
                    switch (str.*) {
                        .string => {},
                        else => {
                            self.logErrLn(0, "Invalid callable", .{});
                            return error.InvalidCallable;
                        },
                    }
                    return self.eval(env, str.string) catch |e| {
                        std.log.err("{any}", .{e});
                        return self.gc.nothing();
                    };
                } else if (std.mem.eql(u8, s, "cons")) {
                    const a = try self.evalAst(env, call.args.items[0]);
                    const b = try self.evalAst(env, call.args.items[1]);
                    return v.cons(self.gc, a, b);
                }
            },
            else => {},
        }

        const fun = switch ((try self.evalAst(env, call.callable)).*) {
            .function => |fun| fun,
            .nativeFunction => |nfun| {
                return self.evalNativeCallFn(env, nfun, call.args);
            },
            else => {
                self.logErrLn(call.callable.meta.line, "Invalid callable", .{});
                return error.InvalidCallable;
            },
        };
        const body = self.function_bodies.items[fun.address];
        var next = fun.env;
        for (0..fun.params.items.len) |i| {
            const param = fun.params.items[i];
            const value = try self.evalAst(env, call.args.items[i]);
            try next.define(param, value);
        }
        return self.evalAst(next, body);
    }

    pub fn evalNativeCallFn(self: *Eval, env: *v.Environment, native: v.NativeFunction, args: std.ArrayList(*ast.Ast)) EvalError!*v.Value {
        var vs = std.ArrayList(*v.Value).init(self.gc.allocator);
        defer vs.deinit();
        for (args.items) |arg| {
            try vs.append(try self.evalAst(env, arg));
        }
        return native(self.gc, vs);
    }

    pub fn evalDot(self: *Eval, env: *v.Environment, dot: ast.Pair) EvalError!*v.Value {
        const a = try self.evalAst(env, dot.a);
        const b = self.gc.symAlloc(dot.b.node.symbol);

        switch (a.*) {
            .dictionary => |d| {
                return d.get(b) orelse self.gc.nothing();
            },
            .nothing => {
                self.logErrLn(0, "Left side of dot operator is undefined", .{});
                return error.Undefined;
            },
            else => {
                self.logErrLn(0, "Left side of dot operator is not a valid value", .{});
                return error.InvalidDotValue;
            },
        }
    }

    pub fn evalIf(self: *Eval, env: *v.Environment, ifx: ast.If) EvalError!*v.Value {
        for (ifx.branches.items) |branch| {
            const cond = try self.evalAst(env, branch.check);
            if (v.isTrue(cond)) {
                return self.evalAst(env, branch.then);
            }
        }
        if (ifx.otherwise) |otherwise| {
            return self.evalAst(env, otherwise);
        }
        return self.gc.nothing();
    }

    pub fn evalWhile(self: *Eval, env: *v.Environment, whilex: ast.While) EvalError!*v.Value {
        var result = self.gc.nothing();
        while (true) {
            const condition_result = try self.evalAst(env, whilex.condition);
            if (v.isFalse(condition_result)) {
                break;
            }
            result = try self.evalAst(env, whilex.block);
        }
        return result;
    }

    pub fn evalFor(self: *Eval, env: *v.Environment, forx: ast.For) EvalError!*v.Value {
        // rewrites into a while loop
        // TODO: move this to a preprocessor step

        // do
        //   next := range(0, 10)
        //   i := next()
        //   while i do
        //     ;; block
        //     i = next()
        //   end
        // end

        const next_str = try self.gc.allocator.alloc(u8, 4);
        const iter_sym = try ast.symAlloc(self.gc.allocator, next_str, .{});
        const iter_call = try ast.call(self.gc.allocator, iter_sym, std.ArrayList(*ast.Ast).init(self.gc.allocator), .{});
        defer ast.deinit(iter_call, self.gc.allocator);

        var body = std.ArrayList(*ast.Ast).init(self.gc.allocator);
        defer body.deinit();

        const define_sym = try ast.sym(self.gc.allocator, next_str, .{});
        defer ast.deinit(define_sym, self.gc.allocator);

        const define_it = try ast.define( //
            self.gc.allocator, //
            define_sym, //
            forx.iterable, //
            .{} //
        );
        defer ast.deinit(define_it, self.gc.allocator);

        const define_index = try ast.define(self.gc.allocator, forx.variable, iter_call, .{});
        defer ast.deinit(define_index, self.gc.allocator);

        try body.append(define_it);
        try body.append(define_index);

        const condition = forx.variable;
        var while_block = forx.block.node.block;
        const assign = try ast.assign(self.gc.allocator, forx.variable, iter_call, .{});
        defer ast.deinit(assign, self.gc.allocator);

        try while_block.append(assign);

        const while_body = try ast.block(self.gc.allocator, while_block, .{});
        defer ast.deinit(while_body, self.gc.allocator);

        const whilex = try ast.whilex(self.gc.allocator, condition, while_body, .{});
        defer ast.deinit(whilex, self.gc.allocator);

        try body.append(whilex);
        const block = try ast.block(self.gc.allocator, body, .{});
        defer ast.deinit(block, self.gc.allocator);
        return self.evalAst(env, block);
    }
};
