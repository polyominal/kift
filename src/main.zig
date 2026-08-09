const std = @import("std");
const Io = std.Io;
const process = std.process;

const kift = @import("kift");

pub fn main(init: std.process.Init) !void {
    const build_options = @import("build_options");
    std.debug.print("[{s}@{s}] Hello, {s}!\n", .{ build_options.version, build_options.git_commit, build_options.name });

    const arena: std.mem.Allocator = init.arena.allocator();

    var args = try process.Args.Iterator.initAllocator(init.minimal.args, arena);
    defer args.deinit();

    // skip program name
    _ = args.next();

    const cmd = args.next() orelse return error.Usage;
    std.debug.print("running command: {s}\n", .{cmd});

    // TODO: dispatch to subcommands based on `cmd`
}
