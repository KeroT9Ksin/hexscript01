const std = @import("std");
const Token = @import("token.zig").Token;
const TokType = @import("token.zig").TokType;

const Allocator = std.mem.Allocator;

pub const Lexer = struct {
    source: []const u8,
    current: usize,
    line: usize,
    start: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, source_code: []const u8) Lexer {
        return Lexer{
            .source = source_code,
            .current = 0,
            .line = 1,
            .start = 0,
            .allocator = allocator,
        };
    }

    fn isAtEnd(self: *const Lexer) bool {
        return self.current >= self.source.len;
    }

    fn peek(self: *const Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *const Lexer, n: usize) u8 {
         if (self.current + n >= self.source.len) return 0;
         return self.source[self.current + n];
    }

    fn advance(self: *Lexer) u8 {
        const char = self.peek();
        if (!self.isAtEnd()) self.current += 1;
        if (char == '\n') self.line += 1;
        return char;
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd() or self.source[self.current] != expected) return false;
        self.current += 1;
        if (expected == '\n') self.line += 1;
        return true;
    }

    fn makeToken(self: *const Lexer, token_type: TokType) Token {
        return Token.init(token_type, self.source[self.start..self.current], self.line);
    }

    fn makeIllegalToken(self: *const Lexer) Token {
         return Token.init(TokType.illegal, self.source[self.start..self.current], self.line);
    }

    fn makeEofToken(self: *const Lexer) Token {
        return Token.init(TokType.eof, "", self.line);
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (true) {
            const char = self.peek();
            switch (char) {
                ' ', '\r', '\t', '\n' => { _ = self.advance(); },
                '/' => {
                    if (self.peekNext(1) == '/') {
                        _ = self.advance(); _ = self.advance();
                        while (!self.isAtEnd() and self.peek() != '\n') _ = self.advance();
                    } else if (self.peekNext(1) == '*') {
                         _ = self.advance(); _ = self.advance();
                         while (!self.isAtEnd()) {
                             if (self.peek() == '*' and self.peekNext(1) == '/') {
                                 _ = self.advance(); _ = self.advance(); break;
                             }
                             _ = self.advance();
                         }
                    } else {
                         return;
                    }
                },
                else => return,
            }
        }
    }

    fn isDigit(char: u8) bool {
        return char >= '0' and char <= '9';
    }

    fn isAlpha(char: u8) bool {
        return (char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z') or char == '_';
    }

    fn number(self: *Lexer) Token {
        while (isDigit(self.peek())) _ = self.advance();
        if (self.peek() == '.' and isDigit(self.peekNext(1))) {
            _ = self.advance();
            while (isDigit(self.peek())) _ = self.advance();
            return self.makeToken(TokType.float);
        }
        return self.makeToken(TokType.int);
    }

    fn string(self: *Lexer) Token {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') self.line += 1;
            _ = self.advance();
        }
        if (self.isAtEnd()) return self.makeIllegalToken();
        _ = self.advance();
        return self.makeToken(TokType.string);
    }

    fn identifier(self: *Lexer) Token {
        while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();
        const lexeme = self.source[self.start..self.current];
        if (std.mem.eql(u8, lexeme, "let")) return self.makeToken(TokType.kw_let);
        if (std.mem.eql(u8, lexeme, "fn")) return self.makeToken(TokType.kw_fn);
        if (std.mem.eql(u8, lexeme, "true")) return self.makeToken(TokType.bool);
        if (std.mem.eql(u8, lexeme, "false")) return self.makeToken(TokType.bool);
        if (std.mem.eql(u8, lexeme, "if")) return self.makeToken(TokType.kw_if);
        if (std.mem.eql(u8, lexeme, "else")) return self.makeToken(TokType.kw_else);
        if (std.mem.eql(u8, lexeme, "return")) return self.makeToken(TokType.kw_return);
        if (std.mem.eql(u8, lexeme, "hex")) return self.makeToken(TokType.kw_hex);
        return self.makeToken(TokType.ident);
    }

    pub fn lex(self: *Lexer) Token {
        self.skipWhitespaceAndComments();
        self.start = self.current;
        if (self.isAtEnd()) return self.makeEofToken();

        const char = self.advance();
        switch (char) {
            '(' => return self.makeToken(TokType.sep_lparen),
            ')' => return self.makeToken(TokType.sep_rparen),
            '{' => return self.makeToken(TokType.sep_lbrace),
            '}' => return self.makeToken(TokType.sep_rbrace),
            ';' => return self.makeToken(TokType.sep_semicolon),
            ',' => return self.makeToken(TokType.sep_comma),
            '=' => return if (self.match('=')) self.makeToken(TokType.op_eq) else self.makeToken(TokType.op_assign),
            '!' => return if (self.match('=')) self.makeToken(TokType.op_not_eq) else self.makeIllegalToken(),
            '<' => return if (self.match('=')) self.makeToken(TokType.op_lte) else self.makeToken(TokType.op_lt),
            '>' => return if (self.match('=')) self.makeToken(TokType.op_gte) else self.makeToken(TokType.op_gt),
            '+' => return self.makeToken(TokType.op_plus),
            '-' => return self.makeToken(TokType.op_minus),
            '*' => return self.makeToken(TokType.op_asterisk),
            '/' => return self.makeToken(TokType.op_slash),
            '"' => return self.string(),
            else => {},
        }
        if (isDigit(char)) return self.number();
        if (isAlpha(char)) return self.identifier();
        return self.makeIllegalToken();
    }
};