// src/parser/ast.zig
const std = @import("std");
const Token = @import("../token/token.zig").Token;

pub const Expression = union(enum) {
    integer: i64,
    float: f64,
    boolean: bool,
    string: []const u8,
    identifier: []const u8,
    prefix: PrefixExpression,
    infix: InfixExpression,
    call: CallExpression,
    function: FunctionLiteral,
};

pub const Statement = union(enum) {
    let: LetStatement,
    expr: ExpressionStatement,
    block: BlockStatement,
};

pub const LetStatement = struct {
    token: Token,
    name: Identifier,
    value: Expression,
};

pub const ExpressionStatement = struct {
    token: Token,
    expression: Expression,
};

pub const Identifier = struct {
    token: Token,
    value: []const u8,
};

pub const PrefixExpression = struct {
    token: Token,
    operator: []const u8,
    right: *Expression,
};

pub const InfixExpression = struct {
    token: Token,
    left: *Expression,
    operator: []const u8,
    right: *Expression,
};

pub const CallExpression = struct {
    token: Token,
    function: *Expression,
    arguments: std.ArrayList(Expression),

    pub fn init(allocator: std.mem.Allocator, token: Token, function: *Expression) CallExpression {
        return CallExpression{
            .token = token,
            .function = function,
            .arguments = std.ArrayList(Expression).init(allocator),
        };
    }
};

pub const BlockStatement = struct {
    token: Token,
    statements: std.ArrayList(*Statement),

    pub fn init(allocator: std.mem.Allocator) BlockStatement {
        return BlockStatement{
            .token = undefined,
            .statements = std.ArrayList(*Statement).init(allocator),
        };
    }
};

pub const FunctionLiteral = struct {
    token: Token,
    parameters: std.ArrayList(Identifier),
    body: *BlockStatement,
};

pub const Program = struct {
    statements: std.ArrayList(*Statement),

    pub fn init(allocator: std.mem.Allocator) Program {
        return Program{
            .statements = std.ArrayList(*Statement).init(allocator),
        };
    }

    pub fn deinit(self: *Program) void {
        self.statements.deinit();
    }

    pub fn debugPrint(self: Program) void {
        for (self.statements.items) |stmt_ptr| {
            std.debug.print("Statement: {any}\n", .{stmt_ptr.*});
        }
    }
};