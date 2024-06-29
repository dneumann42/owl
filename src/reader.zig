// Version 1 of the reader

const v = @import("values.zig");
const std = @import("std");
const ascii = std.ascii;

pub const Reader = struct {
    allocator: std.mem.Allocator,
    code: []const u8,
    it: usize,
    end: usize,

    pub fn init(allocator: std.mem.Allocator) Reader {
        return Reader{ .allocator = allocator, .code = "", .it = 0, .end = 0 };
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
    pub fn read_expression() v.Value {}

    // logical_or = logical_and, {"or", logical_and};
    pub fn read_binary_logical_or() v.Value {}

    // logical_and = equality, {"or", logical_equality};
    pub fn read_binary_logical_end() v.Value {}

    // equality = comparison, {("==" | "!="), comparison};
    pub fn read_equality() v.Value {}

    // comparison = additive, {("<" | ">" | "<=" | ">="), additive};
    pub fn read_comparison() v.Value {}

    // additive = multiplicative, {("+" | "-"), multiplicative}
    pub fn read_additive() v.Value {}

    // multiplicative = unary, {("*" | "/"), unary};
    pub fn read_multiplicative() v.Value {}

    // unary = unary_operator, unary
    //       | primary;
    pub fn read_unary() v.Value {}

    // unary_operator = "-" | "not" | "~" | "'";
    pub fn read_unary_operator() v.Value {}

    // primary = literal
    //         | identifier
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
    pub fn read_primary() v.Value {}

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
    pub fn read_literal() v.Value {}

    // number = float = digit, {digit}, ".", digit, {digit};
    pub fn read_number() v.Value {}

    // string = '"', {any_character}, '"';
    pub fn read_string() v.Value {}

    // boolean = "true" | "false";
    pub fn read_boolean() v.Value {}

    // list = "[", [expression, {",", expression}], "]";
    pub fn read_list() v.Value {}

    // dictionary = "{", [key_value_pair, {",", key_value_pair}], "}";
    pub fn read_dictionary() v.Value {}

    // key_value_pair = (symbol | string), ":", expression;
    pub fn read_key_value_pair() v.Value {}

    // symbol
    pub fn read_symbol() v.Value {}
};

pub fn read(allocator: std.mem.Allocator, code: []const u8) v.Value {
    return Reader.init_load(allocator, code).read_program();
}
