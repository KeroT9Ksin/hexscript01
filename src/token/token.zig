const std = @import("std");

pub const TokType = enum {
    int, float, string, ident, bool,
    kw_let, kw_fn, kw_true, kw_false, kw_if, kw_else, kw_return, kw_hex,
    op_assign, op_plus, op_minus, op_asterisk, op_slash,
    op_eq, op_not_eq, op_lt, op_gt, op_lte, op_gte,
    sep_lparen, sep_rparen, sep_lbrace, sep_rbrace, sep_semicolon, sep_comma,
    comment,
    eof,
    illegal,
};

pub const Token = struct {
    type: TokType,
    lexeme: []const u8,
    line: usize,

    pub fn init(token_type: TokType, lexeme_text: []const u8, line_number: usize) Token {
        return Token{
            .type = token_type,
            .lexeme = lexeme_text,
            .line = line_number,
        };
    }

    pub fn format(self: Token, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{{{s} '{s}' @{d}}}", .{ @tagName(self.type), self.lexeme, self.line });
    }
};