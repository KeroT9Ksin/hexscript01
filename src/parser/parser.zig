// src/parser/parser.zig
const std = @import("std");
const Lexer = @import("../token/lexer.zig").Lexer;
const Token = @import("../token/token.zig").Token;
const TokType = @import("../token/token.zig").TokType;
const ast = @import("ast.zig");
const Statement = ast.Statement;
const Expression = ast.Expression;
const Identifier = ast.Identifier;

const Allocator = std.mem.Allocator;

pub const Parser = struct {
    lexer: Lexer,
    current_token: Token,
    peek_token: Token,
    errors: std.ArrayList([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator, lexer: Lexer) Parser {
        var parser = Parser{
            .lexer = lexer,
            .current_token = undefined,
            .peek_token = undefined,
            .errors = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
        parser.nextToken();
        parser.nextToken();
        return parser;
    }

    pub fn deinit(self: *Parser) void {
        self.errors.deinit();
    }

    fn nextToken(self: *Parser) void {
        self.current_token = self.peek_token;
        self.peek_token = self.lexer.lex();
    }

    fn expectPeek(self: *Parser, token_type: TokType) bool {
        if (self.peek_token.type == token_type) {
            self.nextToken();
            return true;
        } else {
            self.peekError(token_type);
            return false;
        }
    }

    fn peekError(self: *Parser, token_type: TokType) void {
        const msg = std.fmt.allocPrint(self.allocator, "expected next token to be {s}, got {s} instead", .{ @tagName(token_type), @tagName(self.peek_token.type) }) catch "error creating error message";
        self.errors.append(msg) catch {};
    }

    pub fn parseProgram(self: *Parser) !ast.Program {
        std.debug.print("DEBUG parseProgram: Start\n", .{});
        var program = ast.Program.init(self.allocator);

        var counter: usize = 0;
        while (self.current_token.type != .eof) {
            counter += 1;
            std.debug.print("DEBUG parseProgram: Loop iteration {d}, current_token: {{{s} '{s}' @{d}}}\n", .{ counter, @tagName(self.current_token.type), self.current_token.lexeme, self.current_token.line });
            if (counter > 100) {
                std.debug.print("DEBUG parseProgram: Emergency exit! Too many iterations.\n", .{});
                break;
            }
            const stmt_o = self.parseStatement() catch |err| {
                std.debug.print("DEBUG parseProgram: Parse statement error: {any}\n", .{err});
                while (self.current_token.type != .sep_semicolon and self.current_token.type != .eof) {
                    self.nextToken();
                }
                if (self.current_token.type == .sep_semicolon) {
                    self.nextToken();
                }
                continue;
            };
            if (stmt_o) |stmt| {
                std.debug.print("DEBUG parseProgram: Statement parsed, appending to program.\n", .{});
                try program.statements.append(stmt);
            } else {
                 std.debug.print("DEBUG parseProgram: parseStatement returned null.\n", .{});
            }
            std.debug.print("DEBUG parseProgram: Calling nextToken() before next iteration.\n", .{});
            self.nextToken();
        }
        std.debug.print("DEBUG parseProgram: Loop finished, returning program.\n", .{});
        return program;
    }

    fn parseStatement(self: *Parser) anyerror!?*Statement {
        std.debug.print("DEBUG parseStatement: called for token {s}\n", .{@tagName(self.current_token.type)});
        const stmt_ptr = switch (self.current_token.type) {
            .kw_let => try self.parseLetStatement(),
            .sep_lbrace => try self.parseBlockStatement(),
            else => try self.parseExpressionStatement(),
        };
        if (stmt_ptr) |_| {
            std.debug.print("DEBUG parseStatement: successfully parsed statement\n", .{});
        } else {
             std.debug.print("DEBUG parseStatement: returned null\n", .{});
        }
        return stmt_ptr;
    }

    fn parseLetStatement(self: *Parser) anyerror!?*Statement {
        const token = self.current_token;

        if (!self.expectPeek(.ident)) {
            return null;
        }

        const name = ast.Identifier{
            .token = self.current_token,
            .value = self.current_token.lexeme,
        };

        if (!self.expectPeek(.op_assign)) {
            return null;
        }

        self.nextToken();

        const value_o = try self.parseExpression(Precedence.Lowest);
        if (value_o) |value| {
            const boxed_value = try self.allocator.create(Expression);
            boxed_value.* = value;

            const let_stmt = try self.allocator.create(ast.LetStatement);
            let_stmt.* = ast.LetStatement{
                .token = token,
                .name = name,
                .value = boxed_value.*,
            };

            const stmt_ptr = try self.allocator.create(Statement);
            stmt_ptr.* = Statement{ .let = let_stmt.* };
            return stmt_ptr;
        } else {
            return null;
        }
    }

    fn parseExpressionStatement(self: *Parser) anyerror!?*Statement {
        const token = self.current_token;
        const expr_o = try self.parseExpression(Precedence.Lowest);
        if (expr_o) |expr| {
            const boxed_expr = try self.allocator.create(Expression);
            boxed_expr.* = expr;

            const expr_stmt = try self.allocator.create(ast.ExpressionStatement);
            expr_stmt.* = ast.ExpressionStatement{
                .token = token,
                .expression = boxed_expr.*,
            };

            const stmt_ptr = try self.allocator.create(Statement);
            stmt_ptr.* = Statement{ .expr = expr_stmt.* };
            return stmt_ptr;
        } else {
            return null;
        }
    }

    fn parseBlockStatement(self: *Parser) anyerror!?*Statement {
        var block = ast.BlockStatement.init(self.allocator);
        block.token = self.current_token;

        self.nextToken();

        while (self.current_token.type != .sep_rbrace and self.current_token.type != .eof) {
            const stmt_o = self.parseStatement() catch |err| {
                std.debug.print("Error parsing statement in block: {any}\n", .{err});
                while (self.current_token.type != .sep_rbrace and self.current_token.type != .eof and self.current_token.type != .sep_semicolon) {
                    self.nextToken();
                }
                if (self.current_token.type == .sep_semicolon) {
                    self.nextToken();
                }
                continue;
            };
            if (stmt_o) |stmt| {
                try block.statements.append(stmt);
            }
        }

        if (self.current_token.type != .sep_rbrace) {
            if (!self.expectPeek(.sep_rbrace)) {
                block.statements.deinit();
                return null;
            }
        }

        const block_ptr = try self.allocator.create(ast.BlockStatement);
        block_ptr.* = block;

        const stmt_ptr = try self.allocator.create(Statement);
        stmt_ptr.* = Statement{ .block = block_ptr.* };
        return stmt_ptr;
    }


    const Precedence = enum {
        Lowest,
        Equals,
        LessGreater,
        Sum,
        Product,
        Prefix,
        Call,
    };

    fn precedenceFor(token_type: TokType) Precedence {
        return switch (token_type) {
            .op_eq, .op_not_eq => Precedence.Equals,
            .op_lt, .op_gt, .op_lte, .op_gte => Precedence.LessGreater,
            .op_plus, .op_minus => Precedence.Sum,
            .op_asterisk, .op_slash => Precedence.Product,
            .sep_lparen => Precedence.Call,
            else => Precedence.Lowest,
        };
    }

    fn parseExpression(self: *Parser, precedence: Precedence) anyerror!?Expression {
        std.debug.print("DEBUG parseExpression: called with precedence={any}, current_token={{{s} '{s}' @{d}}}\n", .{ precedence, @tagName(self.current_token.type), self.current_token.lexeme, self.current_token.line });
        
        var left_expr: ?Expression = switch (self.current_token.type) {
            .ident => blk: {
                std.debug.print("DEBUG parseExpression: parsing identifier '{s}'\n", .{self.current_token.lexeme});
                break :blk Expression{ .identifier = self.current_token.lexeme };
            },
            .int => blk: {
                const val = std.fmt.parseInt(i64, self.current_token.lexeme, 10) catch 0;
                std.debug.print("DEBUG parseExpression: parsing integer {d}\n", .{val});
                break :blk Expression{ .integer = val };
            },
            .float => blk: {
                const val = std.fmt.parseFloat(f64, self.current_token.lexeme) catch 0.0;
                std.debug.print("DEBUG parseExpression: parsing float {d}\n", .{val});
                break :blk Expression{ .float = val };
            },
            .string => blk: {
                 std.debug.print("DEBUG parseExpression: parsing string '{s}'\n", .{self.current_token.lexeme});
                 break :blk Expression{ .string = self.current_token.lexeme };
            },
            .bool => blk: {
                const val = std.mem.eql(u8, self.current_token.lexeme, "true");
                std.debug.print("DEBUG parseExpression: parsing boolean {any}\n", .{val});
                break :blk Expression{ .boolean = val };
            },
            .op_minus => (try self.parsePrefixExpression()) orelse {
                 std.debug.print("DEBUG parseExpression: parsePrefixExpression returned null\n", .{});
                 return null;
            },
            .kw_fn => (try self.parseFunctionLiteral()) orelse {
                std.debug.print("DEBUG parseExpression: parseFunctionLiteral returned null\n", .{});
                return null;
            },
            else => {
                std.debug.print("DEBUG parseExpression: no prefix parser for {s}\n", .{@tagName(self.current_token.type)});
                return null;
            },
        };

        if (left_expr == null) {
            std.debug.print("DEBUG parseExpression: left_expr is null, returning null\n", .{});
            return null;
        }

        std.debug.print("DEBUG parseExpression: initial left_expr created: {any}\n", .{std.meta.activeTag(left_expr.?)});

        var loop_counter: usize = 0;
        while (self.peek_token.type != .sep_semicolon and self.peek_token.type != .eof and @intFromEnum(precedence) < @intFromEnum(precedenceFor(self.peek_token.type))) {
            loop_counter += 1;
            std.debug.print("DEBUG parseExpression: LOOP ITERATION {d}\n", .{loop_counter});
            if (loop_counter > 50) {
                std.debug.print("DEBUG parseExpression: Emergency exit from infix loop! Too many iterations.\n", .{});
                break;
            }
            std.debug.print("DEBUG parseExpression: infix loop iteration {d}, peek_token={{{s} '{s}' @{d}}}, current precedence={any}, peek precedence={any}\n", .{ loop_counter, @tagName(self.peek_token.type), self.peek_token.lexeme, self.peek_token.line, precedence, precedenceFor(self.peek_token.type) });

            if (self.peek_token.type == .sep_lparen) {
                std.debug.print("DEBUG parseExpression: infix loop, found '(', calling parseCallExpression\n", .{});
                self.nextToken();
                const boxed_left = try self.allocator.create(Expression);
                boxed_left.* = left_expr.?;
                left_expr = (try self.parseCallExpression(boxed_left)) orelse {
                    std.debug.print("DEBUG parseExpression: parseCallExpression returned null\n", .{});
                    return null;
                };
                std.debug.print("DEBUG parseExpression: parseCallExpression succeeded\n", .{});
                continue;
            }

            switch (self.peek_token.type) {
                .op_plus, .op_minus, .op_asterisk, .op_slash, .op_eq, .op_not_eq, .op_lt, .op_gt, .op_lte, .op_gte => {
                    std.debug.print("DEBUG parseExpression: infix loop, found operator '{s}', calling parseInfixExpression\n", .{self.peek_token.lexeme});
                    self.nextToken();
                    const boxed_left = try self.allocator.create(Expression);
                    boxed_left.* = left_expr.?;
                    left_expr = self.parseInfixExpression(boxed_left) catch |err| {
                         std.debug.print("DEBUG parseExpression: parseInfixExpression failed: {any}\n", .{err});
                         return err;
                    };
                    std.debug.print("DEBUG parseExpression: parseInfixExpression succeeded\n", .{});
                },
                else => {
                    std.debug.print("DEBUG parseExpression: infix loop, found unknown token '{s}', breaking\n", .{@tagName(self.peek_token.type)});
                    break;
                },
            }
        }

        std.debug.print("DEBUG parseExpression: finished, returning {any}\n", .{std.meta.activeTag(left_expr.?)});
        return left_expr.?;
    }

    fn parsePrefixExpression(self: *Parser) anyerror!?Expression {
         const token = self.current_token;
         const operator = self.current_token.lexeme;

         self.nextToken();

         const right_expr_o = try self.parseExpression(Precedence.Prefix);
         if (right_expr_o) |right_expr| {
             const boxed_right = try self.allocator.create(Expression);
             boxed_right.* = right_expr;

             const prefix_expr = ast.PrefixExpression{
                 .token = token,
                 .operator = operator,
                 .right = boxed_right,
             };

             return Expression{ .prefix = prefix_expr };
         } else {
             std.debug.print("DEBUG parsePrefixExpression: Missing operand for prefix operator '{s}'\n", .{operator});
             return null;
         }
    }

    fn parseInfixExpression(self: *Parser, left: *Expression) anyerror!Expression {
        const token = self.current_token;
        const operator = self.current_token.lexeme;

        const precedence = precedenceFor(self.current_token.type);
        self.nextToken();

        const right_expr_o = try self.parseExpression(precedence) orelse {
             std.debug.print("DEBUG parseInfixExpression: Missing right operand for infix operator '{s}'\n", .{operator});
             return error.MissingRightOperand;
        };

        const boxed_right = try self.allocator.create(Expression);
        boxed_right.* = right_expr_o;

        const infix_expr = ast.InfixExpression{
            .token = token,
            .left = left,
            .operator = operator,
            .right = boxed_right,
        };

        return Expression{ .infix = infix_expr };
    }

    fn parseCallExpression(self: *Parser, function: *Expression) anyerror!?Expression {
        const token = self.current_token;

        var call_expr = ast.CallExpression.init(self.allocator, token, function);

        if (self.peek_token.type == .sep_rparen) {
            self.nextToken();
            if (self.peek_token.type == .sep_semicolon) {
                self.nextToken();
            }
            const boxed_call = try self.allocator.create(Expression);
            boxed_call.* = Expression{ .call = call_expr };
            return boxed_call.*;
        }

        self.nextToken();

        const first_arg_o = try self.parseExpression(Precedence.Lowest);
        if (first_arg_o) |first_arg| {
            try call_expr.arguments.append(first_arg);
        } else {
            std.debug.print("Expected expression for first argument in call\n", .{});
            call_expr.arguments.deinit();
            return null;
        }

        while (self.peek_token.type == .sep_comma) {
            self.nextToken();
            self.nextToken();

            const arg_o = try self.parseExpression(Precedence.Lowest);
            if (arg_o) |arg| {
                try call_expr.arguments.append(arg);
            } else {
                std.debug.print("Expected expression for argument in call\n", .{});
                call_expr.arguments.deinit();
                return null;
            }
        }

        if (!self.expectPeek(.sep_rparen)) {
            call_expr.arguments.deinit();
            return null;
        }

        if (self.peek_token.type == .sep_semicolon) {
            self.nextToken();
        }

        const boxed_call = try self.allocator.create(Expression);
        boxed_call.* = Expression{ .call = call_expr };
        return boxed_call.*;
    }

    fn parseFunctionLiteral(self: *Parser) anyerror!?Expression {
        std.debug.print("DEBUG parseFunctionLiteral: Start parsing function literal\n", .{});
        const token = self.current_token;

        if (!self.expectPeek(.sep_lparen)) {
            return null;
        }

        var parameters = std.ArrayList(Identifier).init(self.allocator);

        if (self.peek_token.type != .sep_rparen) {
            self.nextToken();
            var ident = Identifier{
                .token = self.current_token,
                .value = self.current_token.lexeme,
            };
            try parameters.append(ident);

            while (self.peek_token.type == .sep_comma) {
                self.nextToken();
                self.nextToken();
                ident = Identifier{
                    .token = self.current_token,
                    .value = self.current_token.lexeme,
                };
                try parameters.append(ident);
            }
        }

        if (!self.expectPeek(.sep_rparen)) {
            parameters.deinit();
            return null;
        }

        if (!self.expectPeek(.sep_lbrace)) {
            parameters.deinit();
            return null;
        }

        const body_ptr = try self.allocator.create(ast.BlockStatement);
        body_ptr.* = ast.BlockStatement.init(self.allocator);
        body_ptr.token = self.current_token;

        self.nextToken();

        // --- ИСПРАВЛЕННЫЙ ЦИКЛ ---
        // ВАЖНО: self.nextToken() должен вызываться В КОНЦЕ КАЖДОЙ ИТЕРАЦИИ
        while (self.current_token.type != .sep_rbrace and self.current_token.type != .eof) {
            const stmt_o = self.parseStatement() catch |err| {
                std.debug.print("Error parsing statement in function body: {any}\n", .{err});
                if (err == error.OutOfMemory) {
                     body_ptr.statements.deinit();
                     self.allocator.destroy(body_ptr);
                     parameters.deinit();
                     return error.OutOfMemory;
                }
                // Пытаемся восстановиться: пропускаем до конца оператора или блока
                while (self.current_token.type != .sep_semicolon and self.current_token.type != .sep_rbrace and self.current_token.type != .eof) {
                    self.nextToken();
                }
                // Пропускаем точку с запятой, если есть
                if (self.current_token.type == .sep_semicolon) {
                    self.nextToken();
                }
                // Продолжаем парсинг тела функции
                continue;
            };
            
            if (stmt_o) |stmt| {
                std.debug.print("DEBUG parseFunctionLiteral: Successfully parsed statement, appending.\n", .{});
                try body_ptr.statements.append(stmt);
            } else {
                 std.debug.print("DEBUG parseFunctionLiteral: parseStatement returned null. Skipping.\n", .{});
                 // Не добавляем null, просто продолжаем
            }
            
            // --- КРИТИЧЕСКОЕ ИЗМЕНЕНИЕ ---
            // self.nextToken() ДОЛЖЕН БЫТЬ ЗДЕСЬ, ВНЕЗАВИСИМОСТЬ ОТ РЕЗУЛЬТАТА stmt_o
            std.debug.print("DEBUG parseFunctionLiteral: Calling nextToken() at end of loop iteration.\n", .{});
            self.nextToken();
            // --- КРИТИЧЕСКОЕ ИЗМЕНЕНИЕ ---
        }
        // --- КОНЕЦ ИСПРАВЛЕННОГО ЦИКЛА ---

        if (self.current_token.type != .sep_rbrace) {
             if (!self.expectPeek(.sep_rbrace)) {
                 body_ptr.statements.deinit();
                 self.allocator.destroy(body_ptr);
                 parameters.deinit();
                 return null;
             }
        }

        const function_lit = ast.FunctionLiteral{
            .token = token,
            .parameters = parameters,
            .body = body_ptr,
        };

        const boxed_function = try self.allocator.create(Expression);
        boxed_function.* = Expression{ .function = function_lit };
        std.debug.print("DEBUG parseFunctionLiteral: Successfully parsed function literal\n", .{});
        return boxed_function.*;
    }
};