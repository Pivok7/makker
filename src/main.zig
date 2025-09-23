const std = @import("std");
const Allocator = std.mem.Allocator;

const embed_main_c = @embedFile("templates/c/main.c");
const embed_main_cpp = @embedFile("templates/cpp/main.cpp");
const embed_main_zig = @embedFile("templates/zig/main.zig");
const embed_build_zig = @embedFile("templates/zig/build.zig");

const c_warn_flags: []const u8 = "-Wall -Wextra -Wno-unused -pedantic";

const Templates = enum{
    none,
    new,
    init_c,
    init_cpp,
    init_zig,
};

const Flags = packed struct{
    silent: bool = false,
    warnings: bool = false,
};

fn printHelp() void {
    std.debug.print("How to use?\n", .{});
    std.debug.print("-> makker [template] [flags]\n", .{});
    std.debug.print("\nTemplates:\n", .{});
    std.debug.print("-> new\n", .{});
    std.debug.print("-> init-c\n", .{});
    std.debug.print("-> init-cpp\n", .{});
    std.debug.print("-> init-zig\n", .{});
    std.debug.print("\n-> Flags:\n", .{});
    std.debug.print("-> -s    --silent    Make Makefile silent:\n", .{});
    std.debug.print("-> -w    --warn      Add basic warnings\n", .{});
}

fn fileExists(file_path: []const u8) !bool {
    std.fs.cwd().access(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return !false,
    };
    return true;
}

fn stdinReadUntilDeliminerAlloc(allocator: Allocator, deliminer: u8) ![]const u8 {
    var stdin_buf: [1024]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&stdin_buf);

    var alloc_writer = std.io.Writer.Allocating.init(allocator);

    _ = try stdin.interface.streamDelimiter(
        &alloc_writer.writer,
        deliminer
    );

    return try alloc_writer.toOwnedSlice();
}

fn addStep(
    allocator: Allocator,
    flags: Flags,
    arr: *std.ArrayList(u8),
    step: []const u8,
    body: []const u8
) !void {
    try arr.appendSlice(allocator, step);
    try arr.appendSlice(allocator, "\n\t");
    if (flags.silent) try arr.append(allocator, '@');
    try arr.appendSlice(allocator, body);
    try arr.appendSlice(allocator, "\n\n");
}

fn askOverride(allocator: Allocator, file_name: []const u8) !bool {
    if (try fileExists(file_name)) {
        std.debug.print("{s} already exists!\n", .{file_name});
        std.debug.print("Do you want to override? [y/N] ", .{});

        const choice = try stdinReadUntilDeliminerAlloc(allocator, '\n');
        defer allocator.free(choice);

        return (std.mem.eql(u8, choice, "y") or std.mem.eql(u8, choice, "Y"));
    }

    return true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var flags: Flags = .{};
    var template = Templates.none;

    const args = try std.process.argsAlloc(allocator);
    errdefer std.process.argsFree(allocator, args);

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            std.process.exit(0);
        }
        else if (std.mem.eql(u8, arg, "-s") or (std.mem.eql(u8, arg, "--silent"))) {
            flags.silent = true;
            continue;
        }
        else if (std.mem.eql(u8, arg, "-w") or (std.mem.eql(u8, arg, "--warn"))) {
            flags.warnings = true;
            continue;
        }
        else if (std.mem.eql(u8, arg, "new")) {
            template = Templates.new;
            continue;
        }
        else if (std.mem.eql(u8, arg, "init-c")) {
            template = Templates.init_c;
            continue;
        }
        else if (std.mem.eql(u8, arg, "init-cpp")) {
            template = Templates.init_cpp;
            continue;
        }
        else if (std.mem.eql(u8, arg, "init-zig")) {
            template = Templates.init_zig;
            continue;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            for (arg) |char| {
                switch (char) {
                    '-' => continue,
                    'w' => flags.warnings = true,
                    's' => flags.silent = true,
                    else => {
                        std.log.err("Invalid flag \"{c}\"", .{char});
                        std.process.exit(2);
                    }
                }
            }
            continue;
        }
        else {
            std.log.err("Unrecognized argument: {s}", .{arg});
            std.process.exit(2);
        }
    }

    switch (template) {
        .none => printHelp(),
        .new => {
            try templateNew(allocator, flags);
        },
        .init_c => {
            try templateC(allocator, flags);
        },
        .init_cpp => {
            try templateCpp(allocator, flags);
        },
        .init_zig => {
            try templateZig(allocator, flags);
        },
    }

}

fn templateNew(allocator: Allocator, flags: Flags) !void {
    if (!try askOverride(allocator, "Makefile")) return;

    var contents = std.ArrayList(u8){};
    defer contents.deinit(allocator);

    std.debug.print("build:\n", .{});
    const build_step = try stdinReadUntilDeliminerAlloc(allocator, '\n');
    defer allocator.free(build_step);

    if (build_step.len > 0) {
        try addStep(allocator, flags, &contents, "build:", build_step);
        std.debug.print("\n", .{});
    } else {
        std.debug.print("Build step can't be empty!\n", .{});
        return error.EmptyBuildStep;
    }

    std.debug.print("run:\n", .{});
    const run_step = try stdinReadUntilDeliminerAlloc(allocator, '\n');
    defer allocator.free(run_step);

    if (run_step.len > 0) {
        try addStep(allocator, flags, &contents, "run: build", run_step);
        std.debug.print("\n", .{});
    }

    std.debug.print("clean:\n", .{});
    const clean_step = try stdinReadUntilDeliminerAlloc(allocator, '\n');
    defer allocator.free(clean_step);

    if (clean_step.len > 0) {
        try addStep(allocator, flags, &contents, "clean:", clean_step);
    }

    const file = try std.fs.cwd().createFile(
        "Makefile",
        .{ .read = true, },
    );
    defer file.close();

    try file.writeAll(contents.items);
}

fn templateC(allocator: Allocator, flags: Flags) !void {
    var contents = std.ArrayList(u8){};
    defer contents.deinit(allocator);

    if (try askOverride(allocator, "main.c")) {
        const main_c = try std.fs.cwd().createFile(
            "main.c",
            .{ .read = true, },
        );
        defer main_c.close();

        try main_c.writeAll(embed_main_c);
        std.debug.print("Created: main.c\n", .{});
    }

    if (try askOverride(allocator, "Makefile")) {
        const makefile = try std.fs.cwd().createFile(
            "Makefile",
            .{ .read = true, },
        );
        defer makefile.close();

        if (flags.warnings) {
            try contents.appendSlice(
                allocator,
                "warn_flags = " ++ c_warn_flags ++ "\n\n"
            );
            try addStep(allocator, flags, &contents, "build:", "gcc -o main main.c $(warn_flags)");
        } else {
            try addStep(allocator, flags, &contents, "build:", "gcc -o main main.c");
        }
        try addStep(allocator, flags, &contents, "run: build", "./main");
        try addStep(allocator, flags, &contents, "clean:", "rm main");
        try makefile.writeAll(contents.items);

        std.debug.print("Created: Makefile\n", .{});
    }
}

fn templateCpp(allocator: Allocator, flags: Flags) !void {
    var contents = std.ArrayList(u8){};
    defer contents.deinit(allocator);

    if (try askOverride(allocator, "main.cpp")) {
        const main_cpp = try std.fs.cwd().createFile(
            "main.cpp",
            .{ .read = true, },
        );
        defer main_cpp.close();

        try main_cpp.writeAll(embed_main_cpp);

        std.debug.print("Created: main.cpp\n", .{});
    }

    if (try askOverride(allocator, "Makefile")) {
        const makefile = try std.fs.cwd().createFile(
            "Makefile",
            .{ .read = true, },
        );
        defer makefile.close();

        if (flags.warnings) {
            try contents.appendSlice(
                allocator,
                "warn_flags = " ++ c_warn_flags ++ "\n\n"
            );
            try addStep(allocator, flags, &contents, "build:", "g++ -o main main.cpp $(warn_flags)");
        } else {
            try addStep(allocator, flags, &contents, "build:", "g++ -o main main.cpp");
        }
        try addStep(allocator, flags, &contents, "run: build", "./main");
        try addStep(allocator, flags, &contents, "clean:", "rm main");
        try makefile.writeAll(contents.items);

        std.debug.print("Created: Makefile\n", .{});
    }
}

fn templateZig(allocator: Allocator, _: Flags) !void {
    if (try askOverride(allocator, "src/main.zig")) {
        _ = try std.fs.cwd().makeOpenPath("src", .{});

        const main_zig = try std.fs.cwd().createFile(
            "src/main.zig",
            .{ .read = true, },
        );
        defer main_zig.close();

        try main_zig.writeAll(embed_main_zig);

        std.debug.print("Created: main.zig\n", .{});
    }

    if (try askOverride(allocator, "build.zig")) {
        const build_zig = try std.fs.cwd().createFile(
            "build.zig",
            .{ .read = true, },
        );
        defer build_zig.close();

        try build_zig.writeAll(embed_build_zig);

        std.debug.print("Created: build.zig\n", .{});
    }
}
