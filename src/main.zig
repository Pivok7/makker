const std = @import("std");

const c_allocator = std.heap.c_allocator;

const Flags = packed struct{
    silent: bool = false,
};

fn fileExists(file_path: []const u8) !bool {
    std.fs.cwd().access(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return !false,
    };
    return true;
}

fn addStep(flags: Flags, arr: *std.ArrayList(u8), step: []const u8, body: []const u8) !void {
    try arr.appendSlice(step);
    try arr.appendSlice("\n\t");
    if (flags.silent) try arr.append('@');
    try arr.appendSlice(body);
    try arr.appendSlice("\n\n");
}

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();

    var flags: Flags = .{};

    const args = try std.process.argsAlloc(c_allocator);
    errdefer std.process.argsFree(c_allocator, args);

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-s")) {
            flags.silent = true;
        }
    }

    if (try fileExists("Makefile")) {
        std.debug.print("Makefile already exists!\n", .{});
        std.debug.print("Do you want to override? [y/N] ", .{});
        const choice = (try stdin.readUntilDelimiterOrEofAlloc(c_allocator, '\n', 64)).?;
        defer c_allocator.free(choice);
        if (!std.mem.eql(u8, choice, "y") and !std.mem.eql(u8, choice, "Y")) {
            std.debug.print("Exiting\n", .{});
            return error.MakefileExists;
        }
    }

    var contents = std.ArrayList(u8).init(c_allocator);
    defer contents.deinit(); 

    std.debug.print("build:\n", .{});
    const build_step = (try stdin.readUntilDelimiterOrEofAlloc(c_allocator, '\n', 1024)).?;
    defer c_allocator.free(build_step);
    if (build_step.len > 0) {
        try addStep(flags, &contents, "build:", build_step);
        std.debug.print("\n", .{});
    } else {
        std.debug.print("Build step can't be empty!\n", .{});
        return error.EmptyBuildStep;
    }

    std.debug.print("run:\n", .{});
    const run_step = (try stdin.readUntilDelimiterOrEofAlloc(c_allocator, '\n', 1024)).?;
    defer c_allocator.free(run_step);
    if (run_step.len > 0) {
        try addStep(flags, &contents, "run:", run_step);
        std.debug.print("\n", .{});
    }

    std.debug.print("clean:\n", .{});
    const clean_step = (try stdin.readUntilDelimiterOrEofAlloc(c_allocator, '\n', 1024)).?;
    defer c_allocator.free(clean_step);
    if (clean_step.len > 0) {
        try addStep(flags, &contents, "clean:", clean_step);
    }

    const file = try std.fs.cwd().createFile(
        "Makefile",
        .{ .read = true, },
    );
    defer file.close();

    try file.writeAll(contents.items);
}
