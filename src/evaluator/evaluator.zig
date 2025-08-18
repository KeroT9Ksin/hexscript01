// src/evaluator/evaluator.zig
const std = @import("std");
const ast = @import("../parser/ast.zig");
const object = @import("object.zig");
const Object = object.Object;
const Environment = object.Environment;
const Allocator = std.mem.Allocator;

pub const Evaluator = struct {
    allocator: Allocator,
    env: *Environment,

    pub fn init(allocator: Allocator) !Evaluator {
        const env = try allocator.create(Environment);
        env.* = Environment.init(allocator);
        return Evaluator{
            .allocator = allocator,
            .env = env,
        };
    }

    pub fn deinit(self: *Evaluator) void {
        self.env.deinit();
        self.allocator.destroy(self.env);
    }

    pub fn eval(self: *Evaluator, node: anytype) anyerror!?Object {
        if (@TypeOf(node) == *ast.Program) {
            return self.evalProgram(node);
        } else if (@TypeOf(node) == *ast.Statement) {
            return self.evalStatement(node);
        } else if (@TypeOf(node) == *ast.Expression) {
            return self.evalExpression(node);
        } else {
            return object.NULL;
        }
    }

    fn evalProgram(self: *Evaluator, program: *ast.Program) anyerror!?Object {
        var result: ?Object = object.NULL;
        for (program.statements.items) |stmt_ptr| {
            result = try self.eval(stmt_ptr);
            if (result) |res| {
                if (std.meta.activeTag(res) == .error) {
                    return res;
                }
            }
        }
        return result;
    }

    fn evalStatement(self: *Evaluator, stmt_ptr: *ast.Statement) anyerror!?Object {
        switch (stmt_ptr.*) {
            .let => |let_stmt| {
                const value_o = try self.evalExpression(&let_stmt.value);
                if (value_o) |value| {
                    if (std.meta.activeTag(value) == .error) {
                        return value;
                    }
                    self.env.set(let_stmt.name.value, value);
                }
                return object.NULL;
            },
            .expr => |expr_stmt| {
                return try self.evalExpression(&expr_stmt.expression);
            },
            .block => |block_stmt| {
                var result: ?Object = object.NULL;
                for (block_stmt.statements.items) |inner_stmt_ptr| {
                    result = try self.eval(inner_stmt_ptr);
                    if (result) |res| {
                        if (std.meta.activeTag(res) == .error) {
                            return res;
                        }
                        // TODO: Handle return
                    }
                }
                return result;
            },
        }
    }

    fn evalExpression(self: *Evaluator, expr_ptr: *ast.Expression) anyerror!?Object {
        switch (expr_ptr.*) {
            .integer => |val| return Object{ .integer = val },
            .float => |val| return Object{ .float = val },
            .boolean => |val| return if (val) object.TRUE else object.FALSE,
            .string => |val| return Object{ .string = val },
            .identifier => |ident_val| {
                if (self.env.get(ident_val)) |value| {
                    return value;
                } else {
                    const err_msg = try std.fmt.allocPrint(self.allocator, "identifier not found: {s}", .{ident_val});
                    return Object{ .error = .{ .message = err_msg } };
                }
            },
            .prefix => |prefix_expr| {
                const right_o = try self.evalExpression(prefix_expr.right);
                if (right_o) |right| {
                    if (std.meta.activeTag(right) == .error) {
                        return right;
                    }
                    return self.evalPrefixExpression(prefix_expr.operator, right);
                } else {
                    return object.NULL;
                }
            },
            .infix => |infix_expr| {
                const left_o = try self.evalExpression(infix_expr.left);
                if (left_o) |left| {
                    if (std.meta.activeTag(left) == .error) {
                        return left;
                    }
                } else {
                    return object.NULL;
                }
                const right_o = try self.evalExpression(infix_expr.right);
                if (right_o) |right| {
                    if (std.meta.activeTag(right) == .error) {
                        return right;
                    }
                } else {
                    return object.NULL;
                }
                if (left_o) |left| {
                    if (right_o) |right| {
                        return self.evalInfixExpression(infix_expr.operator, left, right);
                    }
                }
                return object.NULL;
            },
            .call => |call_expr| {
                const function_o = try self.evalExpression(call_expr.function);
                if (function_o == null orelse std.meta.activeTag(function_o.?) == .error) {
                    return function_o;
                }

                var args = std.ArrayList(Object).init(self.allocator);
                defer args.deinit();

                for (call_expr.arguments.items) |arg_expr| {
                    const arg_o = try self.evalExpression(&arg_expr);
                    if (arg_o) |arg| {
                        if (std.meta.activeTag(arg) == .error) {
                            return arg;
                        }
                        try args.append(arg);
                    } else {
                        const err_msg = "argument evaluation failed";
                        return Object{ .error = .{ .message = err_msg } };
                    }
                }

                return self.applyFunction(function_o.?, args.items);
            },
            .function => |fn_lit| {
                const fn_obj = object.Function{
                    .parameters = fn_lit.parameters,
                    .body = fn_lit.body,
                    .env = self.env,
                };
                return Object{ .function = fn_obj };
            },
        }
    }

    fn evalPrefixExpression(self: *Evaluator, operator: []const u8, right: Object) ?Object {
        if (std.mem.eql(u8, operator, "-")) {
            switch (right) {
                .integer => |val| return Object{ .integer = -val },
                .float => |val| return Object{ .float = -val },
                else => {
                    const err_msg = try std.fmt.allocPrint(self.allocator, "unknown operator: -{s}", .{@tagName(std.meta.activeTag(right))});
                    return Object{ .error = .{ .message = err_msg } };
                },
            }
        } else if (std.mem.eql(u8, operator, "!")) {
            switch (right) {
                .boolean => |val| return Object{ .boolean = !val },
                .null_value => return object.TRUE,
                else => return object.FALSE,
            }
        }
        const err_msg = try std.fmt.allocPrint(self.allocator, "unknown prefix operator: {s}{s}", .{ operator, @tagName(std.meta.activeTag(right)) });
        return Object{ .error = .{ .message = err_msg } };
    }

    fn evalInfixExpression(self: *Evaluator, operator: []const u8, left: Object, right: Object) ?Object {
        if (std.meta.activeTag(left) == .integer and std.meta.activeTag(right) == .integer) {
            const left_val = left.integer;
            const right_val = right.integer;
            if (std.mem.eql(u8, operator, "+")) {
                return Object{ .integer = left_val + right_val };
            }
            if (std.mem.eql(u8, operator, "-")) {
                return Object{ .integer = left_val - right_val };
            }
            if (std.mem.eql(u8, operator, "*")) {
                return Object{ .integer = left_val * right_val };
            }
            if (std.mem.eql(u8, operator, "/")) {
                if (right_val == 0) {
                    const err_msg = "division by zero";
                    return Object{ .error = .{ .message = err_msg } };
                }
                return Object{ .integer = @divTrunc(left_val, right_val) };
            }
            if (std.mem.eql(u8, operator, "==")) {
                return if (left_val == right_val) object.TRUE else object.FALSE;
            }
            if (std.mem.eql(u8, operator, "!=")) {
                return if (left_val != right_val) object.TRUE else object.FALSE;
            }
            if (std.mem.eql(u8, operator, "<")) {
                return if (left_val < right_val) object.TRUE else object.FALSE;
            }
            if (std.mem.eql(u8, operator, ">")) {
                return if (left_val > right_val) object.TRUE else object.FALSE;
            }
        } else if (std.meta.activeTag(left) == .float and std.meta.activeTag(right) == .float) {
             const left_val = left.float;
             const right_val = right.float;
             if (std.mem.eql(u8, operator, "+")) {
                 return Object{ .float = left_val + right_val };
             }
             if (std.mem.eql(u8, operator, "-")) {
                 return Object{ .float = left_val - right_val };
             }
             if (std.mem.eql(u8, operator, "*")) {
                 return Object{ .float = left_val * right_val };
             }
             if (std.mem.eql(u8, operator, "/")) {
                 if (right_val == 0.0) {
                     const err_msg = "division by zero";
                     return Object{ .error = .{ .message = err_msg } };
                 }
                 return Object{ .float = left_val / right_val };
             }
             if (std.mem.eql(u8, operator, "==")) {
                 return if (left_val == right_val) object.TRUE else object.FALSE;
             }
             if (std.mem.eql(u8, operator, "!=")) {
                 return if (left_val != right_val) object.TRUE else object.FALSE;
             }
             if (std.mem.eql(u8, operator, "<")) {
                 return if (left_val < right_val) object.TRUE else object.FALSE;
             }
             if (std.mem.eql(u8, operator, ">")) {
                 return if (left_val > right_val) object.TRUE else object.FALSE;
             }
        } else if (std.meta.activeTag(left) == .boolean and std.meta.activeTag(right) == .boolean) {
             const left_val = left.boolean;
             const right_val = right.boolean;
             if (std.mem.eql(u8, operator, "==")) {
                 return if (left_val == right_val) object.TRUE else object.FALSE;
             }
             if (std.mem.eql(u8, operator, "!=")) {
                 return if (left_val != right_val) object.TRUE else object.FALSE;
             }
        } else {
            if (std.mem.eql(u8, operator, "==")) {
                return if (std.meta.eql(left, right)) object.TRUE else object.FALSE;
            }
            if (std.mem.eql(u8, operator, "!=")) {
                return if (!std.meta.eql(left, right)) object.TRUE else object.FALSE;
            }
        }

        const err_msg = try std.fmt.allocPrint(self.allocator, "unknown operator: {s} {s} {s}", .{ @tagName(std.meta.activeTag(left)), operator, @tagName(std.meta.activeTag(right)) });
        return Object{ .error = .{ .message = err_msg } };
    }

    fn applyFunction(self: *Evaluator, fn_obj: Object, args: []const Object) anyerror!?Object {
        if (std.meta.activeTag(fn_obj) != .function) {
            const err_msg = "not a function";
            return Object{ .error = .{ .message = err_msg } };
        }

        const function = fn_obj.function;
        const extended_env = try self.allocator.create(Environment);
        extended_env.* = Environment.initEnclosed(self.allocator, function.env);

        if (function.parameters.items.len != args.len) {
            const err_msg = try std.fmt.allocPrint(self.allocator, "wrong number of arguments: expected {d}, got {d}", .{ function.parameters.items.len, args.len });
            defer self.allocator.free(err_msg);
            extended_env.deinit();
            self.allocator.destroy(extended_env);
            return Object{ .error = .{ .message = err_msg } };
        }

        for (function.parameters.items, 0..) |param, i| {
            extended_env.set(param.value, args[i]);
        }

        const old_env = self.env;
        self.env = extended_env;
        defer {
            self.env = old_env;
            extended_env.deinit();
            self.allocator.destroy(extended_env);
        }

        const evaluated = try self.evalStatement(&ast.Statement{ .block = function.body.* });
        if (evaluated) |result| {
            if (std.meta.activeTag(result) == .error) {
                return result;
            }
        }
        return evaluated;
    }
};