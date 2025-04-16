const std = @import("std");
const v = @import("value.zig");
const g = @import("gc.zig");
const r = @import("reader.zig");
const Value = v.Value;
const Gc = g.Gc;
const Reader = r.Reader;
const Ast = r.Ast;
const bprint = std.fmt.bufPrint;

pub const EvalError = error{ Undefined, Parser, Memory, Call, Define, InvalidSpecialForm };

pub const Evaluator = struct {
    gc: Gc,
    allocator: std.mem.Allocator,
    config: Config,

    error_message: [1024]u8 = undefined,

    line: usize = 0,
    column: usize = 0,

    const Config = struct {
        dumpAst: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, cfg: Config) !@This() {
        return @This(){ .gc = try Gc.init(allocator), .allocator = allocator, .config = cfg };
    }

    pub fn installLibrary(self: *Evaluator, bindings: []const v.ForeignFunctionBinding) !void {
        for (bindings) |bind| {
            try self.gc.put(self.gc.environment, self.gc.symbol(bind.name), self.gc.ffun(bind.ffun));
        }
    }

    pub fn deinit(self: *Evaluator) void {
        self.gc.deinit();
    }

    pub fn evalString(self: *Evaluator, environment: *v.Environment, code: []const u8) EvalError!*Value {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var reader = Reader.init(arena.allocator());
        reader.load(code);
        const ast = reader.read() catch {
            std.log.err("{s}\n", .{bprint(&self.error_message, "Reader error", .{}) catch unreachable});
            return error.Parser;
        };
        if (self.config.dumpAst) {
            r.debugPrint(ast);
        }
        const value = try self.evalNode(environment, ast, &reader);
        return self.gc.getValue(try self.eval(environment, value));
    }

    pub fn evalNode(self: *Evaluator, environment: *v.Environment, node: *Ast, reader: *Reader) EvalError!usize {
        return switch (node.*.value) {
            .number => |n| self.gc.number(n),
            .string => |s| self.gc.string(s),
            .symbol => |s| self.gc.symbol(s),
            .boolean => |b| self.gc.boolean(b),
            .list => |xs| {
                var list = std.ArrayList(usize).init(self.gc.allocator);
                for (xs.items) |item| {
                    const value = try self.evalNode(environment, item, reader);
                    list.append(value) catch {
                        return error.Memory;
                    };
                }
                return self.gc.list(list);
            },
        };
    }

    pub fn eval(self: *Evaluator, environment: *v.Environment, value_index: usize) !usize {
        const value = self.gc.getValue(value_index);
        return switch (value.*) {
            .number, .string, .boolean, .nothing, .ffun, .fun => value_index,
            .symbol => self.evalSymbol(environment, value_index, value),
            .list => |xs| self.evalList(environment, xs),
        };
    }

    pub fn evalList(self: *Evaluator, environment: *v.Environment, xs: std.ArrayList(usize)) EvalError!usize {
        if (xs.items.len == 0) {
            return error.Call;
        }
        const first = xs.items[0];

        switch (self.gc.getValue(first).*) {
            .symbol => |s| {
                if (std.mem.eql(u8, s, "define")) {
                    return self.evalDefine(environment, xs);
                } else if (std.mem.eql(u8, s, "do")) {
                    for (1..xs.items.len) |i| {
                        const val = try self.eval(environment, xs.items[i]);
                        if (i == xs.items.len - 1) {
                            return val;
                        }
                    }
                    return self.gc.nothing();
                }
            },
            else => {},
        }

        switch (self.gc.getValue(try self.eval(environment, first)).*) {
            .ffun => |fun| {
                for (1..xs.items.len) |i| {
                    xs.items[i] = try self.eval(environment, xs.items[i]);
                }
                return fun(&self.gc, xs.items[1..xs.items.len]) orelse self.gc.nothing();
            },
            .fun => |fun| {
                for (1..xs.items.len) |i| {
                    const arg = try self.eval(environment, xs.items[i]);
                    const psym = fun.params.items[i - 1];
                    const sym = self.gc.symbol(psym);
                    fun.env.put(sym, arg) catch return error.Call;
                }
                return self.eval( //
                    self.gc.environment.push() catch return error.Memory, //
                    fun.body //
                );
            },
            else => {
                _ = bprint(&self.error_message, "Invalid callable", .{}) catch unreachable;
                return error.Call;
            },
        }
    }

    pub fn evalDefine(self: *Evaluator, environment: *v.Environment, xs: std.ArrayList(usize)) !usize {
        if (xs.items.len < 3) {
            return error.Define;
        }

        switch (self.gc.getValue(xs.items[1]).*) {
            .list => |defun| {
                var params = std.ArrayList([]const u8).init(self.gc.allocator);
                const sym = defun.items[0];
                for (1..defun.items.len) |i| {
                    const ident = self.gc.getValue(defun.items[i]);
                    const str = self.gc.allocator.alloc(u8, ident.symbol.len) catch return error.Define;
                    @memcpy(str, self.gc.getValue(defun.items[i]).symbol);
                    params.append(str) catch return error.Define;
                }
                const vfun = self.gc.fun(environment, params, xs.items[2]);
                self.gc.put(environment, sym, vfun) catch return error.Define;
                return vfun;
            },
            .symbol => {
                const val = try self.eval(environment, xs.items[2]);
                self.gc.put(environment, xs.items[1], val) catch return error.Define;
                return val;
            },
            else => {
                _ = bprint(&self.error_message, "Invalid define", .{}) catch unreachable;
                return error.Define;
            },
        }
    }

    pub fn evalSymbol(self: *Evaluator, environment: *v.Environment, symbol_index: usize, symbol: *Value) !usize {
        return self.gc.find(environment, symbol_index) orelse {
            _ = bprint(&self.error_message, "Undefined symbol: {s}", .{symbol.symbol}) catch unreachable;
            return error.Undefined;
        };
    }

    pub fn isCallable(value: *Value) bool {
        return switch (value.*) {
            .ffun, .fun => true,
            else => false,
        };
    }
};
