const std = @import("std");

const git_commit_unknown = "unknown";

pub fn build(b: *std.Build) !void {
    // We've only tested building on these two targets.
    // Let's whitelist them for now.
    const target = b.standardTargetOptions(.{
        .whitelist = &.{
            .{ .cpu_arch = .aarch64, .os_tag = .macos },
            .{ .cpu_arch = .x86_64, .os_tag = .linux },
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const os_dir = switch (target.result.os.tag) {
        .macos => "macos",
        .linux => "linux",
        else => return error.UnsupportedTarget,
    };

    const name = b.option(
        []const u8,
        "name",
        "What to greet",
    ) orelse "world";

    const git_commit = blk: {
        const result = std.process.run(b.allocator, b.graph.io, .{
            .argv = &.{ "git", "rev-parse", "--short", "HEAD" },
        }) catch break :blk git_commit_unknown;

        break :blk switch (result.term) {
            .exited => |code| if (code == 0) std.mem.trim(u8, result.stdout, &std.ascii.whitespace) else git_commit_unknown,
            else => git_commit_unknown,
        };
    };

    const libusb_lib = blk: {
        const upstream = b.lazyDependency("libusb", .{}) orelse break :blk null;
        const lib = b.addLibrary(.{
            .name = "libusb",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
            .linkage = .static,
        });
        lib.root_module.addIncludePath(b.path("vendor/libusb"));
        lib.root_module.addIncludePath(b.path(b.fmt("vendor/libusb/{s}", .{os_dir})));
        lib.root_module.addIncludePath(upstream.path("libusb"));
        const platform_srcs: []const []const u8 = switch (target.result.os.tag) {
            .macos => &.{"os/darwin_usb.c"},
            .linux => &.{ "os/linux_usbfs.c", "os/linux_netlink.c" },
            else => unreachable,
        };
        lib.root_module.addCSourceFiles(.{
            .root = upstream.path("libusb"),
            .files = &.{
                "core.c",
                "descriptor.c",
                "hotplug.c",
                "io.c",
                "strerror.c",
                "sync.c",
                "os/events_posix.c",
                "os/threads_posix.c",
            },
            .flags = &.{ "-fvisibility=hidden", "-pthread" },
        });
        lib.root_module.addCSourceFiles(.{
            .root = upstream.path("libusb"),
            .files = platform_srcs,
            .flags = &.{ "-fvisibility=hidden", "-pthread" },
        });
        if (target.result.os.tag.isDarwin()) {
            lib.root_module.linkFramework("IOKit", .{});
            lib.root_module.linkFramework("CoreFoundation", .{});
            lib.root_module.linkFramework("Security", .{});
        }
        break :blk lib;
    };

    const libmtp_lib = blk: {
        const upstream = b.lazyDependency("libmtp", .{}) orelse break :blk null;
        const lub = libusb_lib orelse break :blk null;
        const libusb_upstream = b.lazyDependency("libusb", .{}) orelse break :blk null;
        const lib = b.addLibrary(.{
            .name = "libmtp",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
            .linkage = .static,
        });
        lib.root_module.addIncludePath(b.path("vendor/libmtp"));
        lib.root_module.addIncludePath(b.path(b.fmt("vendor/libmtp/{s}", .{os_dir})));
        lib.root_module.addIncludePath(upstream.path("src"));
        // libusb-glue.h includes <libusb.h> from our libusb dependency.
        lib.root_module.addIncludePath(libusb_upstream.path("libusb"));
        lib.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = &.{
                "libmtp.c",
                "unicode.c",
                "util.c",
                "playlist-spl.c",
                "ptp.c",
                "libusb1-glue.c",
            },
            .flags = &.{
                "-fvisibility=hidden",
                // libmtp 1.1.23 has a signed-shift UB bug (ptp-pack.c:103,
                // le32atoh) tripped by the my Kindle Colorsoft's
                // FreeSpaceInImages=0xFFFFFFFF🥴; Debug C builds panic on it
                // otherwise.
                "-fno-sanitize=shift",
            },
        });
        lib.root_module.linkLibrary(lub);
        // iconv is not part of libSystem on macOS?
        if (target.result.os.tag == .macos) {
            lib.root_module.linkSystemLibrary("iconv", .{});
        }
        break :blk lib;
    };

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "name", name);
    build_options.addOption([]const u8, "version", "2.3.3");
    build_options.addOption([]const u8, "git_commit", git_commit);

    const abi_translate = std.Build.Step.TranslateC.create(b, .{
        .root_source_file = b.path("vendor/libmtp/libmtp.h"),
        .target = target,
        .optimize = optimize,
    });
    abi_translate.addIncludePath(b.path("vendor/libmtp"));
    const abi_module = abi_translate.createModule();

    const mod = b.addModule("kift", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "libmtp_translated", .module = abi_module },
        },
    });
    // The C libs must be reachable from the module too, so the test step
    // (b.addTest on mod) can link LIBMTP_* / libusb symbols.
    if (libusb_lib) |l| mod.linkLibrary(l);
    if (libmtp_lib) |l| mod.linkLibrary(l);

    const exe = b.addExecutable(.{
        .name = "kift",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "kift", .module = mod },
            },
        }),
    });
    exe.root_module.addOptions("build_options", build_options);
    if (libusb_lib) |l| exe.root_module.linkLibrary(l);
    if (libmtp_lib) |l| exe.root_module.linkLibrary(l);

    // `zig build detect`
    const detect = b.addExecutable(.{
        .name = "detect",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/detect.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    if (libusb_lib) |l| detect.root_module.linkLibrary(l);
    if (libmtp_lib) |l| detect.root_module.linkLibrary(l);
    b.installArtifact(detect);
    const detect_step = b.step("detect", "Detect and dump connected MTP devices");
    const detect_cmd = b.addRunArtifact(detect);
    detect_step.dependOn(&detect_cmd.step);
    detect_cmd.step.dependOn(b.getInstallStep());
    detect_cmd.addPassthruArgs();

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
