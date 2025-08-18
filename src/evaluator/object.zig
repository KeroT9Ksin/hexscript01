// src/evaluator/object.zig
const std = @import("std");
const ast = @import("../parser/ast.zig");
const Allocator = std.mem.Allocator;

pub const ObjectType = enum {
    integer,
    float,
    boolean,
    string,
    null_value,
    function,
    error,
};

pub const Object = union(enum) {
    integer: i64,
    float: f64,
    boolean: bool,
    string: []const u8,
    null_value: void,
    function: Function,
    error: Error,
};

pub const Function = struct {
    parameters: std.ArrayList(ast.Identifier),
    body: *ast.BlockStatement,
    env: *Environment,
};

pub const Error = struct {
    message: []const u8,
};

pub const Environment = @import("environment.zig").Environment;

pub const TRUE = Object{ .boolean = true };
pub const FALSE = Object{ .boolean = false };
pub const NULL = Object{ .null_value = {} };

pub fn inspect(obj: Object) []const u8 {
    switch (obj) {
        .integer => |val| return std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{val}) catch "integer",
        .float => |val| return std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{val}) catch "float",
        .boolean => |val| return if (val) "true" else "false",
        .string => |val| return val,
        .null_value => return "null",
        .function => return "function",
        .error => |e| return e.message,
    }
}