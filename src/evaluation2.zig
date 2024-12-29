// works directly on the ast

const v = @import("values.zig");
const r = @import("reader2.zig");
const g = @import("gc.zig");
const ast = @import("ast.zig");
const std = @import("std");
// const pretty = @import("pretty");
const assert = std.debug.assert;
const nothing = v.nothing;

pub const EvalError = error{ KeyNotFound, OutOfMemory, NotImplemented, ReaderError, UndefinedSymbol, InvalidUnexp, ValueError, InvalidFunction, InvalidCallable, InvalidBinexp, InvalidLExpr };

pub const Eval = struct {
    gc: *g.Gc,

    error_log: std.ArrayList([]const u8),
    function_bodies: std.ArrayList(*ast.Ast),

    pub fn init(gc: *g.Gc) Eval {
        return Eval{
            .gc = gc, //
            .error_log = std.ArrayList([]const u8).init(gc.allocator), //
            .function_bodies = std.ArrayList(*ast.Ast).init(gc.allocator),
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
        const msg = std.fmt.allocPrint(self.gc.allocator, fmt, args) catch unreachable;
        self.error_log.append(msg) catch unreachable;
    }

    pub fn getErrorLog(self: *Eval) ![]const u8 {
        return std.mem.join(self.gc.allocator, "\n", self.error_log.items);
    }

    pub fn eval(self: *Eval, code: []const u8) EvalError!*v.Value {
        var reader = r.Reader.init(self.gc.allocator, code) catch {
            return error.ReaderError;
        };
        const node = switch (reader.read()) {
            .success => |n| n,
            .failure => {
                return error.ReaderError;
            },
        };

        return self.evalNode(node);
    }

    pub fn evalNode(self: *Eval, node: *ast.Ast) EvalError!*v.Value {
        switch (node.*) {
            .number, .boolean => {
                return ast.buildValueFromAst(self.gc, node) catch {
                    return error.ValueError;
                };
            },
            .dictionary => |d| {
                var dict = try v.Dictionary.init(self.gc);
                for (d.items) |kv| {
                    const key = self.gc.sym(kv.key.symbol);
                    const value = try self.evalNode(kv.value);
                    try dict.putOrReplace(key, value);
                }
                return self.gc.create(.{ .dictionary = dict });
            },
            .symbol => |s| {
                if (self.gc.env().find(s)) |value| {
                    return value;
                }
                self.logErr("Undefined symbol '{s}'", .{s});
                return error.UndefinedSymbol;
            },
            .definition => |define| {
                return self.evalDefinition(define);
            },
            .assignment => |assign| {
                return self.evalAssignment(assign);
            },
            .block => |xs| {
                return self.evalBlock(xs);
            },
            .binexp => |bin| {
                return self.evalBinexp(bin);
            },
            .unexp => |un| {
                return self.evalUnexp(un);
            },
            .func => |fun| {
                return self.evalFunc(fun);
            },
            .call => |call| {
                return self.evalCall(call);
            },
            .dot => |dot| {
                return self.evalDot(dot);
            },
            .ifx => |ifx| {
                return self.evalIf(ifx);
            },
            .list => |xs| {
                return self.evalList(xs);
            },
            else => {},
        }

        return error.NotImplemented;
    }

    pub fn evalBlock(self: *Eval, xs: std.ArrayList(*ast.Ast)) EvalError!*v.Value {
        var value: *v.Value = self.gc.nothing();
        for (xs.items) |node| {
            value = try self.evalNode(node);
        }
        return value;
    }

    pub fn evalBinexp(self: *Eval, bin: ast.Binexp) EvalError!*v.Value {
        const left = (try self.evalNode(bin.a)).toNumber();
        const right = (try self.evalNode(bin.b)).toNumber();
        return if (std.mem.eql(u8, bin.op.symbol, "+"))
            self.gc.num(left + right)
        else if (std.mem.eql(u8, bin.op.symbol, "-"))
            self.gc.num(left - right)
        else if (std.mem.eql(u8, bin.op.symbol, "*"))
            self.gc.num(left * right)
        else if (std.mem.eql(u8, bin.op.symbol, "/"))
            self.gc.num(left / right)
        else if (std.mem.eql(u8, bin.op.symbol, "<"))
            self.gc.boolean(left < right)
        else if (std.mem.eql(u8, bin.op.symbol, ">"))
            self.gc.boolean(left > right)
        else {
            self.logErr("Unexpected binary operator '{s}'", .{bin.op.symbol});
            return error.InvalidBinexp;
        };
    }

    pub fn evalUnexp(self: *Eval, un: ast.Unexp) EvalError!*v.Value {
        if (std.mem.eql(u8, un.op.symbol, "-")) {
            return self.gc.num(-un.value.number);
        }
        if (std.mem.eql(u8, un.op.symbol, "not")) {
            switch (un.value.*) {
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
        return error.InvalidUnexp;
    }

    pub fn evalDefinition(self: *Eval, define: ast.Define) EvalError!*v.Value {
        const sym = define.left.symbol;
        const value = try self.evalNode(define.right);
        try self.gc.env().set(sym, value);
        return value;
    }

    pub fn reduceLExpr(self: *Eval, dot: ast.Dot) EvalError!*v.Value {
        switch (dot.a.*) {
            .symbol => |s| {
                return self.gc.env().find(s) orelse self.gc.nothing();
            },
            .dot => |d| {
                const dict = try self.reduceLExpr(d);
                const key = self.gc.sym(d.b.symbol);
                return dict.dictionary.get(key) orelse self.gc.nothing();
            },
            .call => |c| {
                return self.evalCall(c);
            },
            else => {
                return self.gc.nothing();
            },
        }
    }

    pub fn evalAssignment(self: *Eval, assign: ast.Assign) EvalError!*v.Value {
        switch (assign.left.*) {
            .dot => |dot| {
                var dict = try self.reduceLExpr(dot);
                const key = self.gc.sym(dot.b.symbol);
                const value = try self.evalNode(assign.right);
                try dict.dictionary.putOrReplace(key, value);
            },
            else => {},
        }

        return self.gc.nothing();
    }

    pub fn evalFunc(self: *Eval, fun: ast.Func) EvalError!*v.Value {
        var fs = std.ArrayList([]const u8).init(self.gc.allocator);
        for (fun.args.items) |arg| {
            fs.append(arg.symbol) catch {
                return error.OutOfMemory;
            };
        }
        const new_environment = v.Environment.init(self.gc.allocator) catch unreachable;
        new_environment.next = self.gc.env();

        const address = try self.addFunctionBody(fun.body);
        const func = self.gc.create(.{ .function2 = v.Function2.init(address, fs, new_environment) }) catch {
            return error.OutOfMemory;
        };

        if (fun.sym) |symbol| {
            try self.gc.env().set(symbol.symbol, func);
        }

        return func;
    }

    pub fn evalList(self: *Eval, xs: std.ArrayList(*ast.Ast)) EvalError!*v.Value {
        var cons: ?*v.Value = null;
        for (xs.items) |item| {
            cons = v.cons(self.gc, try self.evalNode(item), cons);
        }
        return cons orelse self.gc.nothing();
    }

    pub fn evalCall(self: *Eval, call: ast.Call) EvalError!*v.Value {
        const fun = switch ((try self.evalNode(call.callable)).*) {
            .function2 => |fun| fun,
            else => {
                return error.InvalidCallable;
            },
        };
        const body = self.function_bodies.items[fun.address];
        var next = try self.gc.newEnv(fun.env);
        for (0..fun.params.items.len) |i| {
            const param = fun.params.items[i];
            const value = try self.evalNode(call.args.items[i]);
            try next.env().set(param, value);
        }
        const old_gc = self.gc;
        self.gc = next;
        const result = try self.evalNode(body);
        self.gc = old_gc;
        return result;
    }

    pub fn evalDot(self: *Eval, dot: ast.Dot) EvalError!*v.Value {
        const a = try self.evalNode(dot.a);
        const b = self.gc.sym(dot.b.symbol);

        switch (a.*) {
            .dictionary => |d| {
                return d.get(b) orelse self.gc.nothing();
            },
            else => {
                return error.NotImplemented;
            },
        }
    }

    pub fn evalIf(self: *Eval, ifx: ast.If) EvalError!*v.Value {
        for (ifx.branches.items) |branch| {
            const cond = try self.evalNode(branch.check);
            if (cond.isTrue()) {
                return self.evalNode(branch.then);
            }
        }

        if (ifx.elseBranch) |elseBranch| {
            return self.evalNode(elseBranch);
        }

        return self.gc.nothing();
    }
};
