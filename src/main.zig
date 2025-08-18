// src/main.zig
const std = @import("std");
const Lexer = @import("token/lexer.zig").Lexer;
const Parser = @import("parser/parser.zig").Parser;
const Program = @import("parser/ast.zig").Program;
const Evaluator = @import("evaluator/evaluator.zig").Evaluator;
const object = @import("evaluator/object.zig");
const Object = object.Object;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source_code =
        \\let five = 5;
        \\let ten = 10;
        \\let add = fn(x, y) { x + y; };
        \\let result = add(five, ten);
        \\result;
    ;

    var lexer = Lexer.init(allocator, source_code);
    var parser = Parser.init(allocator, lexer);
    defer parser.deinit();

    var program = parser.parseProgram() catch |err| {
        std.debug.print("Parsing error: {any}\n", .{err});
        return err;
    };
    defer program.deinit();

    var evaluator = try Evaluator.init(allocator);
    defer evaluator.deinit();

    const result_o = try evaluator.eval(&program);
    if (result_o) |result| {
        if (std.meta.activeTag(result) == .error) {
            std.debug.print("Evaluation error: {s}\n", .{result.error.message});
        } else {
            std.debug.print("Program result: {s}\n", .{object.inspect(result)});
        }
    } else {
        std.debug.print("Program returned no value or null.\n", .{});
    }

    if (parser.errors.items.len > 0) {
        std.debug.print("\nParser errors:\n", .{});
        for (parser.errors.items) |err| {
            std.debug.print("  {s}\n", .{err});
        }
    }
}