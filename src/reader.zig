// Version 1 of the reader

const v = @import("values.zig");
const std = @import("std");
const ascii = std.ascii;
const print = std.debug.print;

const ParseError = error{ NoMatch, Invalid };

pub const Reader = struct {
    allocator: std.mem.Allocator,
    code: []const u8,
    it: usize,
    end: usize,

    pub fn init(allocator: std.mem.Allocator) Reader {
        return Reader{ .allocator = allocator, .code = "", .it = 0, .end = 0 };
    }

    pub fn deinit(self: *Reader, val: *v.Value) void {
        switch (val.*) {
            .cons => {
                var it: ?*v.Value = val;
                while (it != null) {
                    if (it) |value| {
                        it = value.cons.cdr;
                        if (value.cons.car) |idx_value| {
                            self.deinit(idx_value);
                        }
                        self.allocator.destroy(value);
                    }
                }
            },
            else => {
                self.allocator.destroy(val);
            },
        }
    }

    pub fn load(self: *Reader, code: []const u8) void {
        self.code = code;
        self.it = 0;
        self.end = code.len;
    }

    pub fn init_load(allocator: std.mem.Allocator, code: []const u8) Reader {
        var reader = Reader.init(allocator);
        reader.load(code);
        return reader;
    }

    pub fn skip_whitespace(self: *Reader) void {
        while (!self.at_eof() and ascii.isWhitespace(self.chr())) {
            self.next();
        }
    }

    pub fn next(self: *Reader) void {
        self.it += 1;
    }

    pub fn chr(self: *Reader) u8 {
        if (self.at_eof())
            return 0;
        return self.code[self.it];
    }

    pub fn at_eof(self: *Reader) bool {
        return self.it >= self.end;
    }

    // program = {expression};
    pub fn read_program() v.Value {}

    // expression = logical_or
    pub fn read_expression(self: *Reader) ParseError!*v.Value {
        return self.read_binary_logical_or();
    }

    pub fn read_binary_expression(
        self: *Reader,
        operator: []const u8,
        left_parse: fn (self: *Reader) ParseError!*v.Value,
        right_parse: fn (self: *Reader) ParseError!*v.Value,
    ) ParseError!*v.Value {
        var pin = self.it;

        const left_value = left_parse(self) catch {
            self.it = pin;
            return error.NoMatch;
        };

        pin = self.it;
        const symbol = self.read_symbol() catch {
            self.it = pin;
            return left_value;
        };

        if (!std.mem.eql(u8, symbol.symbol, operator)) {
            self.allocator.destroy(symbol);
            self.it = pin;
            return left_value;
        }

        const right_value = right_parse(self) catch {
            self.allocator.destroy(symbol);
            self.it = pin;
            return left_value;
        };

        return v.cons(self.allocator, symbol, v.cons(self.allocator, left_value, v.cons(self.allocator, right_value, null)));
    }

    // logical_or = logical_and, {"or", logical_or};
    pub fn read_binary_logical_or(self: *Reader) ParseError!*v.Value {
        return self.read_binary_expression("or", Reader.read_binary_logical_and, Reader.read_binary_logical_or);
    }

    // logical_and = equality, {"and", logical_and};
    pub fn read_binary_logical_and(self: *Reader) ParseError!*v.Value {
        return self.read_binary_expression("and", Reader.read_equality, Reader.read_binary_logical_and);
    }

    // equality = comparison, {("==" | "!="), equality};
    pub fn read_equality(self: *Reader) ParseError!*v.Value {
        if (self.read_binary_expression("==", Reader.read_comparison, Reader.read_equality)) |n| {
            return n;
        } else |_| {}
        if (self.read_binary_expression("!=", Reader.read_comparison, Reader.read_equality)) |n| {
            return n;
        } else |_| {}
        return error.NoMatch;
    }

    // comparison = additive, {("<" | ">" | "<=" | ">="), comparison};
    pub fn read_comparison(self: *Reader) ParseError!*v.Value {
        if (self.read_binary_expression("<", Reader.read_additive, Reader.read_comparison)) |n| {
            return n;
        } else |_| {}
        if (self.read_binary_expression(">", Reader.read_additive, Reader.read_comparison)) |n| {
            return n;
        } else |_| {}
        if (self.read_binary_expression("<=", Reader.read_additive, Reader.read_comparison)) |n| {
            return n;
        } else |_| {}
        if (self.read_binary_expression(">=", Reader.read_additive, Reader.read_comparison)) |n| {
            return n;
        } else |_| {}
        return error.NoMatch;
    }

    // additive = multiplicative, {("+" | "-"), additive}
    pub fn read_additive(self: *Reader) ParseError!*v.Value {
        if (self.read_binary_expression("+", Reader.read_multiplicative, Reader.read_additive)) |n| {
            return n;
        } else |_| {}
        if (self.read_binary_expression("-", Reader.read_multiplicative, Reader.read_additive)) |n| {
            return n;
        } else |_| {}
        return error.NoMatch;
    }

    // multiplicative = unary, {("*" | "/"), multiplicative};
    pub fn read_multiplicative(self: *Reader) ParseError!*v.Value {
        if (self.read_binary_expression("*", Reader.read_unary, Reader.read_multiplicative)) |n| {
            return n;
        } else |_| {}
        if (self.read_binary_expression("/", Reader.read_unary, Reader.read_multiplicative)) |n| {
            return n;
        } else |_| {}
        return error.NoMatch;
    }

    // unary = unary_operator, primary
    //       | primary;
    pub fn read_unary(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        const op = self.read_unary_operator() catch {
            self.it = start;
            return self.read_primary();
        };
        const primary = self.read_primary() catch {
            self.it = start;
            self.allocator.destroy(op);
            return error.NoMatch;
        };

        return v.cons(self.allocator, op, v.cons(self.allocator, primary, null));
    }

    // unary_operator = "-" | "not" | "~" | "'";
    pub fn read_unary_operator(self: *Reader) ParseError!*v.Value {
        if (self.chr() == '-' or self.chr() == '~' or self.chr() == '\'') {
            const val = self.allocator.create(v.Value) catch |err| {
                std.debug.panic("Panicked at Error: {any}", .{err});
            };
            const slice = self.code[self.it .. self.it + 1];
            val.* = .{ .symbol = slice };
            self.next();
            return val;
        }

        const pin = self.it;
        const symbol = self.read_symbol() catch {
            self.it = pin;
            return error.NoMatch;
        };

        if (!std.mem.eql(u8, symbol.symbol, "not")) {
            self.allocator.destroy(symbol);
            self.it = pin;
            return error.NoMatch;
        }

        return symbol;
    }

    // primary = literal
    //         | symbol
    //         | function_call
    //         | list_comprehension
    //         | dict_comprehension
    //         | "(", expression, ")"
    //         | block
    //         | if_expression
    //         | for_expression
    //         | return_expression
    //         | assignment
    //         | function_definition;
    pub fn read_primary(self: *Reader) ParseError!*v.Value {
        if (self.read_literal()) |value| {
            return value;
        } else |_| {}
        if (self.read_symbol()) |value| {
            return value;
        } else |_| {}
        if (self.read_number()) |value| {
            return value;
        } else |_| {}

        // WIP
        return error.NoMatch;
    }

    // function_definition = identifier, parameter_list, ["->" type], block;
    pub fn read_function_definition() v.Value {}

    // parameter_list = "(", [parameter, {",", parameter}], ")";
    pub fn read_parameter_list() v.Value {}

    // parameter = identifier, ":", type;
    pub fn read_parameter() v.Value {}

    // type = simple_type | list_type | dict_type;
    pub fn read_type() v.Value {}

    // simple_type = "int" | "float" | "str" | "bool";
    pub fn read_simple_type() v.Value {}

    // list_type = "list", "[", type, "]";
    pub fn read_list_type() v.Value {}

    // dict_type = "dict", "[", type, ",", type, "]";
    pub fn read_dict_type() v.Value {}

    // block = "$(", {expression}, ")";
    pub fn read_block() v.Value {}

    // assignment = "def", identifier, [":", type], "=", expression;
    pub fn read_assignment() v.Value {}

    // if_expression = "if", "(", expression, ")", expression, ["else", expression];
    pub fn read_if_expression() v.Value {}

    // for_expression = "for", "(", identifier, "in", expression, ")", expression;
    pub fn read_for_expression() v.Value {}

    // return_expression = "return", expression;
    pub fn read_return_expression() v.Value {}

    // function_call = symbol, "(", [expression, {",", expression}], ")";
    pub fn read_function_call() v.Value {}

    // literal = number | string | boolean | list | dictionary;
    pub fn read_literal(self: *Reader) ParseError!*v.Value {
        self.skip_whitespace();
        const start = self.it;
        return self.read_number() catch
            self.read_string() catch
            self.read_boolean() catch {
            self.it = start;
            return error.NoMatch;
        };
    }

    // number = float = digit, {digit}, ".", digit, {digit};
    pub fn read_number(self: *Reader) ParseError!*v.Value {
        // for now I just read integers
        if (!ascii.isDigit(self.chr()))
            return error.NoMatch;
        const start = self.it;
        while (!self.at_eof() and ascii.isDigit(self.chr())) {
            self.next();
        }
        self.next();
        if (start == self.it)
            return error.NoMatch;
        const slice = self.code[start .. self.it - 1];
        const number: f64 = std.fmt.parseFloat(f64, slice) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
        const val = self.allocator.create(v.Value) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
        val.* = .{ .number = number };
        return val;
    }

    // string = '"', {any_character}, '"';
    pub fn read_string(self: *Reader) ParseError!*v.Value {
        if (self.chr() != '"') {
            return error.NoMatch;
        }
        const start = self.it + 1;
        while (!self.at_eof()) {
            self.next();
            if (self.chr() == '"') {
                self.next();
                break;
            }
        }
        const val = self.allocator.create(v.Value) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
        val.* = .{ .string = self.code[start .. self.it - 1] };
        return val;
    }

    // boolean = "true" | "false";
    pub fn make_boolean(self: *Reader, b: bool) *v.Value {
        const val = self.allocator.create(v.Value) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
        val.* = .{ .boolean = b };
        return val;
    }
    pub fn read_boolean(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        const sym = self.read_symbol() catch |err| switch (err) {
            else => {
                self.it = start;
                return error.NoMatch;
            },
        };
        defer self.deinit(sym);
        return switch (sym.*) {
            .symbol => |s| if (std.mem.eql(u8, s, "true"))
                self.make_boolean(true)
            else if (std.mem.eql(u8, s, "false"))
                self.make_boolean(false)
            else {
                self.it = start;
                return error.NoMatch;
            },
            else => {
                self.it = start;
                return error.NoMatch;
            },
        };
    }

    // list = "[", [expression, {",", expression}], "]";
    pub fn read_list(reader: *Reader) ParseError!*v.Value {
        if (reader.chr() != '[') {
            return error.NoMatch;
        }
        //
        return error.NoMatch;
    }

    // dictionary = "{", [key_value_pair, {",", key_value_pair}], "}";
    pub fn read_dictionary() v.Value {}

    // key_value_pair = (symbol | string), ":", expression;
    pub fn read_key_value_pair() v.Value {}

    // symbol
    pub fn read_symbol(reader: *Reader) ParseError!*v.Value {
        const start = reader.it;
        while (!reader.at_eof() and !ascii.isWhitespace(reader.chr())) {
            reader.next();
        }
        if (reader.it == start) {
            return error.NoMatch;
        }
        const val = reader.allocator.create(v.Value) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
        val.* = .{ .symbol = reader.code[start..reader.it] };
        return val;
    }
};

pub fn read(allocator: std.mem.Allocator, code: []const u8) v.Value {
    return Reader.init_load(allocator, code).read_program();
}
