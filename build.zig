// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "hexscript",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const token_module = b.addModule("token", .{
        .source_file = .{ .path = "src/token/token.zig" },
    });

    const ast_module = b.addModule("ast", .{
        .source_file = .{ .path = "src/parser/ast.zig" },
    });

    const parser_module = b.addModule("parser", .{
        .source_file = .{ .path = "src/parser/parser.zig" },
    });

    const evaluator_module = b.addModule("evaluator", .{
        .source_file = .{ .path = "src/evaluator/object.zig" },
    });

    exe.addModule("token", token_module);
    exe.addModule("ast", ast_module);
    exe.addModule("parser", parser_module);
    exe.addModule("evaluator", evaluator_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the interpreter test");
    run_step.dependOn(&run_cmd.step);
}