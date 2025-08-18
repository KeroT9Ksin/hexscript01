// src/evaluator/environment.zig
const std = @import("std");
const Object = @import("object.zig").Object;
const Allocator = std.mem.Allocator;

pub const Environment = struct {
    store: std.StringHashMap(Object),
    outer: ?*Environment,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Environment {
        return Environment{
            .store = std.StringHashMap(Object).init(allocator),
            .outer = null,
            .allocator = allocator,
        };
    }

    pub fn initEnclosed(allocator: Allocator, outer: *Environment) Environment {
        var env = Environment.init(allocator);
        env.outer = outer;
        return env;
    }

    pub fn deinit(self: *Environment) void {
        self.store.deinit();
    }

    pub fn get(self: *Environment, name: []const u8) ?Object {
        if (self.store.get(name)) |value| {
            return value;
        } else if (self.outer) |outer| {
            return outer.get(name);
        }
        return null;
    }

    pub fn set(self: *Environment, name: []const u8, value: Object) void {
        self.store.put(name, value) catch {};
    }
};