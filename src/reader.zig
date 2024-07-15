// Version 1 of the reader

const v = @import("values.zig");
const std = @import("std");
const gc = @import("gc.zig");
const ascii = std.ascii;
const print = std.debug.print;

const ParseError = error{ NoMatch, Invalid };

pub const Reader = struct {
    gc: *gc.Gc,
    code: []const u8,
    it: usize,
    end: usize,

    pub fn init(g: *gc.Gc) Reader {
        return Reader{ .gc = g, .code = "", .it = 0, .end = 0 };
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
                    }
                }
            },
            else => {},
        }
    }

    pub fn load(self: *Reader, code: []const u8) void {
        self.code = code;
        self.it = 0;
        self.end = code.len;
    }

    pub fn initLoad(g: *gc.Gc, code: []const u8) Reader {
        var reader = Reader.init(g);
        reader.load(code);
        return reader;
    }

    pub fn skipWhitespace(self: *Reader) void {
        while (!self.atEof() and ascii.isWhitespace(self.chr())) {
            self.next();
        }
    }

    pub fn next(self: *Reader) void {
        self.it += 1;
    }

    pub fn chr(self: *Reader) u8 {
        if (self.atEof())
            return 0;
        return self.code[self.it];
    }

    pub fn atEof(self: *Reader) bool {
        return self.it >= self.end;
    }

    // program = {expression};
    pub fn readProgram(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        var it: ?*v.Value = v.cons(self.gc, self.gc.create(.{ .symbol = "do" }) catch null, null);
        while (!self.atEof() and it != null) {
            const expr = self.readExpression() catch {
                self.it = start;
                break;
            };
            it = v.cons(self.gc, expr, it);
        }

        if (it) |xs| {
            return xs.reverse();
        }
        return error.NoMatch;
    }

    // expression = logical_or
    pub fn readExpression(self: *Reader) ParseError!*v.Value {
        self.skipWhitespace();
        return self.readBinaryLogicalOr();
    }

    pub fn readBinaryExpression2(
        self: *Reader,
        operators: []const []const u8,
        left_parse: fn (self: *Reader) ParseError!*v.Value,
        right_parse: fn (self: *Reader) ParseError!*v.Value,
    ) ParseError!*v.Value {
        var pin = self.it;

        const left_value = left_parse(self) catch {
            self.it = pin;
            return error.NoMatch;
        };

        self.skipWhitespace();
        pin = self.it;
        const symbol = self.readSymbol(false) catch {
            self.it = pin;
            return left_value;
        };

        var operator_match = false;
        for (operators) |operator| {
            if (std.mem.eql(u8, symbol.symbol, operator)) {
                operator_match = true;
                break;
            }
        }

        if (!operator_match) {
            self.it = pin;
            return left_value;
        }

        self.skipWhitespace();
        const right_value = right_parse(self) catch {
            self.it = pin;
            return left_value;
        };

        switch (right_value.*) {
            v.Value.cons => {
                var op = v.cons(self.gc, null, null);
                op.cons.car = symbol;
                op.cons.cdr = v.cons(self.gc, left_value, v.cons(self.gc, right_value, null));
                return op;
            },
            else => {},
        }

        return v.cons(self.gc, symbol, v.cons(self.gc, left_value, v.cons(self.gc, right_value, null)));
    }

    pub fn readBinaryExpression(
        self: *Reader,
        operator: []const u8,
        left_parse: fn (self: *Reader) ParseError!*v.Value,
        right_parse: fn (self: *Reader) ParseError!*v.Value,
    ) ParseError!*v.Value {
        return readBinaryExpression2(self, &[_][]const u8{operator}, left_parse, right_parse);
    }

    // logical_or = logical_and, {"or", logical_or};
    pub fn readBinaryLogicalOr(self: *Reader) ParseError!*v.Value {
        return self.readBinaryExpression("or", Reader.readBinaryLogicalAnd, Reader.readBinaryLogicalOr);
    }

    // logical_and = equality, {"and", logical_and};
    pub fn readBinaryLogicalAnd(self: *Reader) ParseError!*v.Value {
        return self.readBinaryExpression("and", Reader.readEquality, Reader.readBinaryLogicalAnd);
    }

    // equality = comparison, {("==" | "!="), equality};
    pub fn readEquality(self: *Reader) ParseError!*v.Value {
        if (self.readBinaryExpression2(&[_][]const u8{ "==", "!=" }, Reader.readComparison, Reader.readEquality)) |n| {
            return n;
        } else |_| {}
        return error.NoMatch;
    }

    // comparison = additive, {("<" | ">" | "<=" | ">="), comparison};
    pub fn readComparison(self: *Reader) ParseError!*v.Value {
        if (self.readBinaryExpression2(&[_][]const u8{ "<", ">", "<=", ">=" }, Reader.readAdditive, Reader.readComparison)) |n| {
            return n;
        } else |_| {}
        return error.NoMatch;
    }

    // additive = multiplicative, {("+" | "-"), additive}
    pub fn readAdditive(self: *Reader) ParseError!*v.Value {
        if (self.readBinaryExpression2(&[_][]const u8{ "+", "-" }, Reader.readMultiplicative, Reader.readAdditive)) |n| {
            return n;
        } else |_| {}
        return error.NoMatch;
    }

    // multiplicative = unary, {("*" | "/"), multiplicative};
    pub fn readMultiplicative(self: *Reader) ParseError!*v.Value {
        if (self.readBinaryExpression2(&[_][]const u8{ "*", "/" }, Reader.readUnary, Reader.readMultiplicative)) |n| {
            return n;
        } else |_| {}
        return error.NoMatch;
    }

    // unary = unary_operator, primary
    //       | primary;
    pub fn readUnary(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        const op = self.readUnaryOperator() catch {
            self.it = start;
            return self.readPrimary();
        };
        const primary = self.readPrimary() catch {
            self.it = start;
            return error.NoMatch;
        };

        return v.cons(self.gc, op, v.cons(self.gc, primary, null));
    }

    // unary_operator = "-" | "not" | "~" | "'";
    pub fn readUnaryOperator(self: *Reader) ParseError!*v.Value {
        if (self.chr() == '-' or self.chr() == '~' or self.chr() == '\'') {
            const slice = self.code[self.it .. self.it + 1];
            const val = self.gc.create(.{ .symbol = slice }) catch |err| {
                std.debug.panic("Panicked at Error: {any}", .{err});
            };
            self.next();
            return val;
        }

        const pin = self.it;
        const symbol = self.readSymbol(false) catch {
            self.it = pin;
            return error.NoMatch;
        };

        if (!std.mem.eql(u8, symbol.symbol, "not")) {
            self.it = pin;
            return error.NoMatch;
        }

        return symbol;
    }

    // primary = literal
    //         | function_call
    //         | symbol
    //         | list_comprehension
    //         | dict_comprehension
    //         | "(", expression, ")"
    //         | block
    //         | if_expression
    //         | for_expression
    //         | return_expression
    //         | assignment
    //         | function_definition;
    pub fn readPrimary(self: *Reader) ParseError!*v.Value {
        if (self.readLiteral()) |value| {
            return value;
        } else |_| {}
        if (self.readFunctionCall()) |value| {
            return value;
        } else |_| {}
        if (self.readSymbol(false)) |value| {
            return value;
        } else |_| {}

        self.skipWhitespace();
        if (self.chr() == '(') {
            self.next();
            const expr = try self.readExpression();
            self.skipWhitespace();
            if (self.chr() == ')') {
                self.next();
                return expr;
            }
        }

        if (self.readBlock()) |value| {
            return value;
        } else |_| {}

        if (self.readIfExpression()) |value| {
            return value;
        } else |_| {}

        // NOTE: we need to check if readSymbol returns a language keyword like 'fun',
        // so we can get to this point
        if (self.readFunctionDefinition()) |value| {
            return value;
        } else |_| {}

        // WIP
        return error.NoMatch;
    }

    // Yields no match if the next expression is not
    // a symbol that matches the 'sym' string
    pub fn expectKeyword(self: *Reader, sym: []const u8) ParseError!void {
        self.skipWhitespace();
        const start = self.it;
        const symbol = self.readSymbol(true) catch {
            self.it = start;
            return error.NoMatch;
        };
        if (!std.mem.eql(u8, symbol.symbol, sym)) {
            self.it = start;
            return error.NoMatch;
        }
    }

    // function_definition = "fun", identifier, parameter_list, ["->" type], block;
    pub fn readFunctionDefinition(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        try self.expectKeyword("fun");
        self.skipWhitespace();
        const literal = self.readSymbol(false) catch {
            self.it = start;
            return error.NoMatch;
        };
        const params = self.readParameterList() catch {
            self.it = start;
            return error.NoMatch;
        };

        const body = self.readBlockTillEnd() catch {
            self.it = start;
            return error.NoMatch;
        };
        return self.gc.create(.{ .function = .{ .name = literal, .body = body, .params = params } }) catch {
            return error.NoMatch;
        };
    }

    // parameter_list = "(", [parameter, {",", parameter}], ")";
    pub fn readParameterList(self: *Reader) ParseError!*v.Value {
        self.skipWhitespace();
        var it: ?*v.Value = null;
        var first = true;

        self.next();
        while (!self.atEof()) {
            defer first = false;
            self.skipWhitespace();
            if (self.chr() == ')') {
                self.next();
                break;
            }
            if (self.chr() == ',' and !first) {
                self.next();
            } else if (!first) {
                std.debug.print("Missing comma got: {c}\n", .{self.chr()});
                return error.NoMatch;
            }
            const start2 = self.it;
            const expr = self.readExpression() catch {
                self.it = start2;
                break;
            };
            it = v.cons(self.gc, expr, it);
        }

        if (it) |list| {
            return list.reverse();
        }

        return error.NoMatch;
    }

    // parameter = identifier, ":", type;
    pub fn readParameter() v.Value {}

    // type = simple_type | list_type | dict_type;
    pub fn readType() v.Value {}

    // simple_type = "int" | "float" | "str" | "bool";
    pub fn readSimpleType() v.Value {}

    // list_type = "list", "[", type, "]";
    pub fn readListType() v.Value {}

    // dict_type = "dict", "[", type, ",", type, "]";
    pub fn readDictType() v.Value {}

    pub fn readBlockTillEnd(self: *Reader) ParseError!*v.Value {
        var it: ?*v.Value = v.cons(self.gc, self.gc.create(.{ .symbol = "do" }) catch unreachable, null);
        const start = self.it;

        while (!self.atEof() and it != null) {
            self.skipWhitespace();

            if (self.atEof()) {
                std.debug.print("Missing closing parenthesis.\n", .{});
                return error.NoMatch;
            }

            const expr = self.readExpression() catch |e| {
                self.it = start;
                return e;
            };

            switch (expr.*) {
                v.Value.symbol => {
                    if (std.mem.eql(u8, expr.symbol, "end")) {
                        break;
                    }
                },
                else => {},
            }

            it = v.cons(self.gc, expr, it);
        }

        if (it) |xs| {
            return xs.reverse();
        }
        return error.NoMatch;
    }

    // block = "do", {expression}, "end";
    pub fn readBlock(self: *Reader) ParseError!*v.Value {
        self.skipWhitespace();
        const start = self.it;
        try self.expectKeyword("do");
        return self.readBlockTillEnd() catch {
            self.it = start;
            return error.NoMatch;
        };
    }

    // assignment = "def", identifier, [":", type], "=", expression;
    pub fn readAssignment() v.Value {}

    // if_expression = "if", expression, "then", expression, ["else", expression], "end";
    pub fn readIfExpression(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        try self.expectKeyword("if");
        const ifsym = self.gc.create(.{ .symbol = "if" }) catch unreachable;
        const condition = try self.readExpression();
        self.expectKeyword("then") catch {
            self.it = start;
            return error.NoMatch;
        };
        const consequent = try self.readExpression();
        const start2 = self.it;
        _ = self.expectKeyword("else") catch {
            self.it = start2;
            try self.expectKeyword("end");
            return v.cons(self.gc, ifsym, v.cons(self.gc, condition, v.cons(self.gc, consequent, null)));
        };
        const alternative = try self.readExpression();
        try self.expectKeyword("end");
        return v.cons(self.gc, ifsym, v.cons(self.gc, condition, v.cons(self.gc, consequent, v.cons(self.gc, alternative, null))));
    }

    // for_expression = "for", identifier, "in", expression, "do", expression;
    pub fn readForExpression() v.Value {}

    // return_expression = "return", expression;
    pub fn readReturnExpression() v.Value {}

    // function_call = symbol, "(", [expression, {",", expression}], ")";
    pub fn readFunctionCall(self: *Reader) ParseError!*v.Value {
        self.skipWhitespace();
        const start = self.it;

        const symbol = self.readSymbol(false) catch {
            self.it = start;
            return error.NoMatch;
        };
        self.skipWhitespace();
        if (self.atEof() or self.chr() != '(') {
            self.it = start;
            return error.NoMatch;
        }

        var it = v.cons(self.gc, symbol, null);
        var first = true;

        self.next();
        while (!self.atEof()) {
            defer first = false;
            self.skipWhitespace();
            if (self.chr() == ')') {
                self.next();
                break;
            }
            if (self.chr() == ',' and !first) {
                self.next();
            } else if (!first) {
                std.debug.print("Missing comma got: {c}\n", .{self.chr()});
                return error.NoMatch;
            }
            const start2 = self.it;
            const expr = self.readExpression() catch {
                self.it = start2;
                break;
            };
            it = v.cons(self.gc, expr, it);
        }

        return it.reverse();
    }

    // literal = number | string | boolean | list | dictionary;
    pub fn readLiteral(self: *Reader) ParseError!*v.Value {
        self.skipWhitespace();
        const start = self.it;
        return self.readNumber() catch
            self.readString() catch
            self.readBoolean() catch {
            self.it = start;
            return error.NoMatch;
        };
    }

    // number = float = digit, {digit}, ".", digit, {digit};
    pub fn readNumber(self: *Reader) ParseError!*v.Value {
        // for now I just read integers
        if (!ascii.isDigit(self.chr())) {
            return error.NoMatch;
        }
        const start = self.it;
        while (!self.atEof() and ascii.isDigit(self.chr())) {
            self.next();
        }
        if (start == self.it) {
            return error.NoMatch;
        }
        const slice = self.code[start..self.it];
        const number: f64 = std.fmt.parseFloat(f64, slice) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
        return self.gc.create(.{ .number = number }) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
    }

    // string = '"', {any_character}, '"';
    pub fn readString(self: *Reader) ParseError!*v.Value {
        if (self.chr() != '"') {
            return error.NoMatch;
        }
        const start = self.it + 1;
        while (!self.atEof()) {
            self.next();
            if (self.chr() == '"') {
                self.next();
                break;
            }
        }
        return self.gc.create(.{ .string = self.code[start .. self.it - 1] }) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
    }

    // boolean = "true" | "false";
    pub fn makeBoolean(self: *Reader, b: bool) *v.Value {
        return self.gc.create(.{ .boolean = b }) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
    }
    pub fn readBoolean(self: *Reader) ParseError!*v.Value {
        const start = self.it;
        const sym = self.readSymbol(false) catch |err| switch (err) {
            else => {
                self.it = start;
                return error.NoMatch;
            },
        };
        defer self.deinit(sym);
        return switch (sym.*) {
            .symbol => |s| if (std.mem.eql(u8, s, "true"))
                self.makeBoolean(true)
            else if (std.mem.eql(u8, s, "false"))
                self.makeBoolean(false)
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
    pub fn readList(reader: *Reader) ParseError!*v.Value {
        if (reader.chr() != '[') {
            return error.NoMatch;
        }
        //
        return error.NoMatch;
    }

    // dictionary = "{", [key_value_pair, {",", key_value_pair}], "}";
    pub fn readDictionary() v.Value {}

    // key_value_pair = (symbol | string), ":", expression;
    pub fn readKeyValuePair() v.Value {}

    // symbol
    pub fn isOwlKeyword(sym: []const u8) bool {
        if (std.mem.eql(u8, sym, "fun")) return true;
        if (std.mem.eql(u8, sym, "if")) return true;
        if (std.mem.eql(u8, sym, "then")) return true;
        if (std.mem.eql(u8, sym, "else")) return true;
        if (std.mem.eql(u8, sym, "for")) return true;
        if (std.mem.eql(u8, sym, "do")) return true;
        if (std.mem.eql(u8, sym, "cond")) return true;
        return false;
    }
    pub fn readSymbol(reader: *Reader, readkeywords: bool) ParseError!*v.Value {
        const start = reader.it;
        if (ascii.isDigit(reader.chr())) {
            return error.NoMatch;
        }
        while (!reader.atEof() and !ascii.isWhitespace(reader.chr()) and Reader.validSymbolCharacter(reader.chr())) {
            reader.next();
        }
        if (reader.it == start) {
            return error.NoMatch;
        }
        const sym = reader.code[start..reader.it];
        if (!readkeywords and isOwlKeyword(sym)) {
            reader.it = start;
            return error.NoMatch;
        }
        return reader.gc.create(.{ .symbol = sym }) catch |err| {
            std.debug.panic("Panicked at Error: {any}", .{err});
        };
    }

    pub fn validSymbolCharacter(ch: u8) bool {
        return switch (ch) {
            '+', '*', '%', '$', '-', '>', '<', '=' => true,
            else => ascii.isAlphanumeric(ch),
        };
    }
};

pub fn read(allocator: std.mem.Allocator, code: []const u8) v.Value {
    return Reader.initLoad(allocator, code).readProgram();
}
