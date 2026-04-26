const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const cwd = std.Io.Dir.cwd;

const io_buf_size = 1024;

const embed_main_c = @embedFile("templates/c/main.c");
const embed_main_cpp = @embedFile("templates/cpp/main.cpp");
const embed_main_zig = @embedFile("templates/zig/main.zig");
const embed_build_zig = @embedFile("templates/zig/build.zig");
const embed_gitignore_zig = @embedFile("templates/zig/.gitignore");
const embed_flake_nix = @embedFile("templates/nix/flake.nix");

const c_warn_flags: []const u8 = "-Wall -Wextra -Wno-unused -pedantic";

const Templates = enum {
    none,
    c,
    cpp,
    zig,
    nix,
};

const Flags = packed struct {
    silent: bool = false,
    warnings: bool = false,
};

fn printHelp() void {
    std.debug.print("How to use?\n", .{});
    std.debug.print("-> makker <c/cpp/zig/nix> [flags]\n", .{});
    std.debug.print("\nExamples:\n", .{});
    std.debug.print("-> makker c\n", .{});
    std.debug.print("-> makker cpp --warn -s\n", .{});
    std.debug.print("\n-> Flags:\n", .{});
    std.debug.print("-> -s / --silent   Make Makefile silent:\n", .{});
    std.debug.print("-> -w / --warn     Add basic warnings\n", .{});
}

fn fileExists(io: Io, file_path: []const u8) !bool {
    cwd().access(io, file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return !false,
    };
    return true;
}

fn stdinReadUntilDeliminerAlloc(allocator: Allocator, io: Io, deliminer: u8) ![]const u8 {
    var stdin_buf: [io_buf_size]u8 = undefined;
    var stdin = Io.File.stdin().reader(io, &stdin_buf);

    var alloc_writer = Io.Writer.Allocating.init(allocator);

    _ = try stdin.interface.streamDelimiter(&alloc_writer.writer, deliminer);

    return try alloc_writer.toOwnedSlice();
}

fn addStep(allocator: Allocator, flags: Flags, arr: *std.ArrayList(u8), step: []const u8, body: []const u8) !void {
    try arr.appendSlice(allocator, step);
    try arr.appendSlice(allocator, "\n\t");
    if (flags.silent) try arr.append(allocator, '@');
    try arr.appendSlice(allocator, body);
    try arr.appendSlice(allocator, "\n\n");
}

fn askOverride(allocator: Allocator, io: Io, file_name: []const u8) !bool {
    if (try fileExists(io, file_name)) {
        std.debug.print("{s} already exists!\n", .{file_name});
        std.debug.print("Do you want to override? [y/N] ", .{});

        const choice = try stdinReadUntilDeliminerAlloc(allocator, io, '\n');
        defer allocator.free(choice);

        return (std.mem.eql(u8, choice, "y") or std.mem.eql(u8, choice, "Y"));
    }

    return true;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var flags: Flags = .{};
    var template = Templates.none;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-s") or (std.mem.eql(u8, arg, "--silent"))) {
            flags.silent = true;
            continue;
        } else if (std.mem.eql(u8, arg, "-w") or (std.mem.eql(u8, arg, "--warn"))) {
            flags.warnings = true;
            continue;
        } else if (std.mem.eql(u8, arg, "c")) {
            template = Templates.c;
            continue;
        } else if (std.mem.eql(u8, arg, "cpp")) {
            template = Templates.cpp;
            continue;
        } else if (std.mem.eql(u8, arg, "zig")) {
            template = Templates.zig;
            continue;
        } else if (std.mem.eql(u8, arg, "nix")) {
            template = Templates.nix;
            continue;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.log.err("Invalid flag \"{s}\"", .{arg});
            std.log.err("Type \"makker --help\" for help", .{});
            std.process.exit(2);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            for (arg) |char| {
                switch (char) {
                    '-' => continue,
                    'w' => flags.warnings = true,
                    's' => flags.silent = true,
                    else => {
                        std.log.err("Invalid flag \"{c}\"", .{char});
                        std.process.exit(2);
                    },
                }
            }
            continue;
        } else {
            std.log.err("Unrecognized argument: {s}", .{arg});
            std.process.exit(2);
        }
    }

    switch (template) {
        .none => printHelp(),
        .c => try templateC(allocator, io, flags),
        .cpp => try templateCpp(allocator, io, flags),
        .zig => try templateZig(allocator, io, flags),
        .nix => try templateNix(allocator, io, flags),
    }
}

fn templateC(allocator: Allocator, io: Io, flags: Flags) !void {
    var contents: std.ArrayList(u8) = .empty;
    defer contents.deinit(allocator);

    if (try askOverride(allocator, io, "main.c")) {
        const main_c = try cwd().createFile(
            io,
            "main.c",
            .{ .read = true },
        );
        defer main_c.close(io);

        try main_c.writeStreamingAll(io, embed_main_c);
        std.debug.print("Created: main.c\n", .{});
    }

    if (try askOverride(allocator, io, "Makefile")) {
        const makefile = try cwd().createFile(
            io,
            "Makefile",
            .{ .read = true },
        );
        defer makefile.close(io);

        if (flags.warnings) {
            try contents.appendSlice(allocator, "warn_flags = " ++ c_warn_flags ++ "\n\n");
            try addStep(allocator, flags, &contents, "build:", "gcc -o main main.c $(warn_flags)");
        } else {
            try addStep(allocator, flags, &contents, "build:", "gcc -o main main.c");
        }
        try addStep(allocator, flags, &contents, "run: build", "./main");
        try addStep(allocator, flags, &contents, "clean:", "rm main");

        try makefile.writeStreamingAll(io, contents.items);
        std.debug.print("Created: Makefile\n", .{});
    }
}

fn templateCpp(allocator: Allocator, io: Io, flags: Flags) !void {
    var contents: std.ArrayList(u8) = .empty;
    defer contents.deinit(allocator);

    if (try askOverride(allocator, io, "main.cpp")) {
        const main_cpp = try cwd().createFile(
            io,
            "main.cpp",
            .{ .read = true },
        );
        defer main_cpp.close(io);

        try main_cpp.writeStreamingAll(io, embed_main_cpp);
        std.debug.print("Created: main.cpp\n", .{});
    }

    if (try askOverride(allocator, io, "Makefile")) {
        const makefile = try cwd().createFile(
            io,
            "Makefile",
            .{ .read = true },
        );
        defer makefile.close(io);

        if (flags.warnings) {
            try contents.appendSlice(allocator, "warn_flags = " ++ c_warn_flags ++ "\n\n");
            try addStep(allocator, flags, &contents, "build:", "g++ -o main main.cpp $(warn_flags)");
        } else {
            try addStep(allocator, flags, &contents, "build:", "g++ -o main main.cpp");
        }
        try addStep(allocator, flags, &contents, "run: build", "./main");
        try addStep(allocator, flags, &contents, "clean:", "rm main");

        try makefile.writeStreamingAll(io, contents.items);
        std.debug.print("Created: Makefile\n", .{});
    }
}

fn templateZig(allocator: Allocator, io: Io, flags: Flags) !void {
    if (flags.silent) std.log.warn("Flag \"silent\" not supported in zig", .{});
    if (flags.warnings) std.log.warn("Flag \"warnings\" not supported in zig", .{});

    if (try askOverride(allocator, io, "src/main.zig")) {
        _ = try cwd().createDirPathOpen(io, "src", .{});

        const main_zig = try cwd().createFile(
            io,
            "src/main.zig",
            .{ .read = true },
        );
        defer main_zig.close(io);

        try main_zig.writeStreamingAll(io, embed_main_zig);
        std.debug.print("Created: main.zig\n", .{});
    }

    if (try askOverride(allocator, io, "build.zig")) {
        const build_zig = try cwd().createFile(
            io,
            "build.zig",
            .{ .read = true },
        );
        defer build_zig.close(io);

        try build_zig.writeStreamingAll(io, embed_build_zig);
        std.debug.print("Created: build.zig\n", .{});
    }

    if (try askOverride(allocator, io, ".gitignore")) {
        const gitignore = try cwd().createFile(
            io,
            ".gitignore",
            .{ .read = true },
        );
        defer gitignore.close(io);

        try gitignore.writeStreamingAll(io, embed_gitignore_zig);
        std.debug.print("Created: .gitignore\n", .{});
    }
}

fn templateNix(allocator: Allocator, io: Io, flags: Flags) !void {
    if (flags.silent) std.log.warn("Flag \"silent\" not supported in nix", .{});
    if (flags.warnings) std.log.warn("Flag \"warnings\" not supported in nig", .{});

    if (try askOverride(allocator, io, "flake.nix")) {
        const flake_nix = try cwd().createFile(
            io,
            "flake.nix",
            .{ .read = true },
        );
        defer flake_nix.close(io);

        try flake_nix.writeStreamingAll(io, embed_flake_nix);
        std.debug.print("Created: flake.nix\n", .{});
    }
}
