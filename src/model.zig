const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const File = struct {
    name: []const u8,
    size: u64,

    fn deinit(file: *const File, allocator: Allocator) void {
        allocator.free(file.name);
    }
};

const Folder = struct {
    name: []const u8,
    children: []const Folder,

    fn deinit(folder: *const Folder, allocator: Allocator) void {
        for (folder.children) |child| {
            child.deinit(allocator);
        }
        allocator.free(folder.name);
        allocator.free(folder.children);
    }

    fn render(folder: *const Folder, writer: *Io.Writer, files: []const File, frame: *const Frame) !void {
        // TODO
        _ = folder;
        _ = writer;
        _ = files;
        _ = frame;
    }
};

const Frame = struct {
    parent: ?*const Frame,
    last: bool,
};

pub const Listing = struct {
    folders: []const Folder,
    files: []const File,

    fn deinit(listing: *const Listing, allocator: Allocator) void {
        for (listing.folders) |folder| {
            folder.deinit(allocator);
        }
        for (listing.files) |file| {
            file.deinit(allocator);
        }
        allocator.free(listing.folders);
        allocator.free(listing.files);
    }

    fn render(listing: *const Listing, writer: *Io.Writer) !void {
        // TODO
        _ = listing;
        _ = writer;
    }
};

pub fn fixture(allocator: Allocator) !Listing {
    const readings = try allocator.alloc(Folder, 1);
    readings[0] = .{ .name = try allocator.dupe(u8, "Readings"), .children = &.{} };

    const amazon_children = try allocator.alloc(Folder, 2);
    amazon_children[0] = .{ .name = try allocator.dupe(u8, "Books"), .children = readings };
    amazon_children[1] = .{ .name = try allocator.dupe(u8, "Periodicals"), .children = &.{} };

    const music_children = try allocator.alloc(Folder, 1);
    music_children[0] = .{ .name = try allocator.dupe(u8, "Albums"), .children = &.{} };

    const roots = try allocator.alloc(Folder, 2);
    roots[0] = .{ .name = try allocator.dupe(u8, "Amazon"), .children = amazon_children };
    roots[1] = .{ .name = try allocator.dupe(u8, "Music"), .children = music_children };

    const files = try allocator.alloc(File, 8);
    files[0] = .{ .name = try allocator.dupe(u8, "cover.png"), .size = 1024 };
    files[1] = .{ .name = try allocator.dupe(u8, "book.pdf"), .size = 2048 };
    files[2] = .{ .name = try allocator.dupe(u8, "reading.txt"), .size = 512 };
    files[3] = .{ .name = try allocator.dupe(u8, "mag.pdf"), .size = 3072 };
    files[4] = .{ .name = try allocator.dupe(u8, "track.mp3"), .size = 8192 };
    files[5] = .{ .name = try allocator.dupe(u8, "album.flac"), .size = 65536 };
    files[6] = .{ .name = try allocator.dupe(u8, "notes.txt"), .size = 64 };
    files[7] = .{ .name = try allocator.dupe(u8, "mystery.dat"), .size = 1 };

    return .{ .folders = roots, .files = files };
}

test "fixture has the expected structure" {
    const a = std.testing.allocator;

    var listing = try fixture(a);
    defer listing.deinit(a);

    try std.testing.expectEqual(@as(usize, 2), listing.folders.len);
    try std.testing.expectEqualStrings("Amazon", listing.folders[0].name);
    try std.testing.expectEqual(@as(usize, 2), listing.folders[0].children.len);
    try std.testing.expectEqualStrings("Readings", listing.folders[0].children[0].children[0].name);
    try std.testing.expectEqualStrings("Albums", listing.folders[1].children[0].name);
    try std.testing.expectEqual(@as(usize, 8), listing.files.len);
}

test "fixture without deinit detected as leaks" {
    var safe = std.heap.SafeAllocator.init(std.heap.page_allocator, .{});
    var counted = std.testing.FailingAllocator.init(safe.allocator(), .{});

    _ = try fixture(counted.allocator());

    try std.testing.expectEqual(counted.allocations, safe.deinitLog(false));
}
