const std = @import("std");
const e = @import("evaluation.zig");
const v = @import("values.zig");
const g = @import("gc.zig");
const a = @import("ast.zig");
const owl_std = @import("base.zig");
const r = @import("reader.zig");
const logger = @import(" logger.zig");

const CoreLib = @embedFile("lib/core.owl");

const ModuleError = error{ IOError, OutOfMemory, ReaderError, EvalError };

pub const ErrorReport = struct {
    line_number: usize,
    char_index: usize,
    message: []const u8,
    path: []const u8,
};

pub const Modules = struct {
    gc: *g.Gc,
    env: *v.Environment,
    evaluator: e.Eval,
    allocator: std.mem.Allocator,
    modules: std.StringHashMap(v.Module),

    reader_error: ?ErrorReport,

    pub fn init(allocator: std.mem.Allocator) Modules {
        const gc = allocator.create(g.Gc) catch unreachable;
        gc.* = g.Gc.init(allocator);

        const env = v.Environment.init(allocator) catch unreachable;
        return Modules{
            .gc = gc, //
            .env = env,
            .evaluator = e.Eval.init(gc),
            .allocator = allocator,
            .modules = std.StringHashMap(v.Module).init(allocator),
            .reader_error = null,
        };
    }

    pub fn deinit(self: *Modules) void {
        self.evaluator.deinit();
        self.env.deinit();
        self.gc.deinit();
        self.allocator.destroy(self.gc);
        self.modules.deinit();
        owl_std.deinitReadline();
    }

    pub fn readAst(self: *Modules, content: []const u8, path: ?[]const u8) !*a.Ast {
        var reader = r.Reader.init(self.allocator, content) catch return error.OutOfMemory;
        defer reader.deinit();
        return switch (reader.read()) {
            .ok => |val| val,
            .err => |err| {
                self.reader_error = ErrorReport{
                    .line_number = reader.countLines(err.start),
                    .char_index = 0,
                    .message = r.getErrorMessage(err),
                    .path = path orelse "",
                };
                return error.ReaderError;
            },
        };
    }

    pub fn getModuleAst(self: *Modules, path: []const u8) ModuleError!*a.Ast {
        var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch {
            const cwd = std.fs.cwd().realpathAlloc(self.allocator, ".") catch return error.IOError;
            std.log.err("File not found '{s}' current working directory '{s}'", .{ path, cwd });
            return error.IOError;
        };

        defer file.close();
        const file_content = file.readToEndAlloc(self.allocator, comptime std.math.maxInt(usize)) catch return error.IOError;
        defer self.allocator.free(file_content);
        return self.readAst(file_content, path);
    }

    pub fn getModuleDependencies(self: *Modules, ast: *a.Ast) !std.ArrayList(a.Use) {
        var uses = std.ArrayList(a.Use).init(self.allocator);
        for (ast.block.items) |node| {
            switch (node.*) {
                .use => |use| {
                    try uses.append(use);
                },
                else => {},
            }
        }
        return uses;
    }

    pub fn loadModuleDependencies(self: *Modules, path: []const u8, log_values: bool) !void {
        if (self.modules.contains(path)) {
            return;
        }

        const ast = try self.getModuleAst(path);
        defer a.deinit(ast, self.allocator);
        const deps = try self.getModuleDependencies(ast);
        const dir = std.fs.path.dirname(path) orelse "";

        for (deps.items) |use| {
            const dep_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.owl", .{ dir, use.name });
            defer self.allocator.free(dep_path);

            try self.loadModuleDependencies(dep_path, log_values);
        }

        const value = try self.evaluator.evalNode(self.env, ast);
        const name = std.fs.path.basename(path);
        const slice = name[0 .. name.len - 4];
        const module = v.Module{ .name = slice, .value = value };

        try self.modules.put(path, module);
        try self.env.define(slice, value);
    }

    pub fn loadString(self: *Modules, code: []const u8) !*v.Value {
        const ast = try self.readAst(code, "<string>");
        return self.evaluator.evalNode(self.env, ast);
    }

    pub fn loadCoreLibrary(self: *Modules, code: []const u8) !void {
        _ = try self.loadString(code);
    }

    pub fn load(self: *Modules, path: []const u8, opts: struct {
        install_core: bool = true,
        install_base: bool = true,
        log_values: bool = false,
    }) !void {
        if (opts.install_base) {
            owl_std.installBase(self.gc, self.env);
        }
        if (opts.install_core) {
            self.loadCoreLibrary(CoreLib) catch |err| switch (err) {
                error.ReaderError => {
                    if (self.reader_error) |reader_err| {
                        std.log.err("{s}:{d}: {s}\n", .{ reader_err.path, reader_err.line_number, reader_err.message });
                    } else {
                        std.log.err("Reader error", .{});
                    }
                },
                else => {
                    const logs = self.evaluator.error_log;
                    if (logs.items.len == 0) {
                        std.log.err("{any}\n", .{err});
                        return;
                    }
                    const log = logs.items[0];
                    std.log.err("{s}:{d}: {s}\n", .{ path, log.line, log.message });
                },
            };
        }

        self.loadModuleDependencies(path, opts.log_values) catch |err| switch (err) {
            error.ReaderError => {
                if (self.reader_error) |reader_err| {
                    std.log.err("{s}:{d}: {s}\n", .{ reader_err.path, reader_err.line_number, reader_err.message });
                } else {
                    std.log.err("Reader error", .{});
                }
            },
            else => {
                logger.log_errors(e.EvalErrorReport, self.evaluator.error_log, .{ .prefix = path });
            },
        };
    }
};
