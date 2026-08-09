const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;

const libmtp = @import("libmtp.zig");
const LIBMTP_file_t = libmtp.LIBMTP_file_t;
const LIBMTP_folder_t = libmtp.LIBMTP_folder_t;

const bar_vertical = "\xe2\x94\x82  "; // │ (U+2502) + two spaces: line continues below
const bar_blank = "   "; // line stops below
const elbow_last = "\xe2\x94\x94\xe2\x94\x80 "; // └ (U+2514) + ─ (U+2500): last child
const elbow_mid = "\xe2\x94\x9c\xe2\x94\x80 "; // ├ (U+251C) + ─ (U+2500): more children

const ID = u32;

const SnapshotError = error{ OutOfMemory, NestingTooDeep };

fn snapshot(
    allocator: Allocator,
    folder_list: ?*LIBMTP_folder_t,
    file_list: ?*LIBMTP_file_t,
    max_depth: usize,
) SnapshotError!Listing {
    var folders: std.ArrayListUnmanaged(Folder) = .empty;
    defer folders.deinit(allocator);
    var raw_folder = folder_list;
    while (raw_folder) |node| {
        const folder = try traverse_folder(allocator, node, 0, max_depth);
        try folders.append(allocator, folder);
        raw_folder = node.sibling;
    }

    var files: std.ArrayListUnmanaged(File) = .empty;
    defer files.deinit(allocator);
    var raw_file = file_list;
    while (raw_file) |node| {
        const file: File = .{
            .id = node.item_id,
            .parent_id = node.parent_id,
            .name = try allocator.dupe(u8, mem.span(node.filename)),
            .size = node.filesize,
        };
        try files.append(allocator, file);
        raw_file = node.next;
    }

    return .{
        .folders = try folders.toOwnedSlice(allocator),
        .files = try files.toOwnedSlice(allocator),
    };
}

fn traverse_folder(
    allocator: Allocator,
    folder: *LIBMTP_folder_t,
    depth: usize,
    max_depth: usize,
) SnapshotError!Folder {
    if (max_depth < depth) {
        return error.NestingTooDeep;
    }

    var children: std.ArrayListUnmanaged(Folder) = .empty;
    defer children.deinit(allocator);
    var child: ?*LIBMTP_folder_t = folder.child;
    while (child) |node| {
        const child_folder = try traverse_folder(allocator, node, depth + 1, max_depth);
        try children.append(allocator, child_folder);
        child = node.sibling;
    }

    return .{
        .id = folder.folder_id,
        .name = try allocator.dupe(u8, mem.span(folder.name)),
        .children = try children.toOwnedSlice(allocator),
    };
}

const File = struct {
    id: ID,
    parent_id: ID,
    name: []const u8,
    size: u64,

    fn deinit(file: *const File, allocator: Allocator) void {
        allocator.free(file.name);
    }

    fn render(file: *const File, writer: *Io.Writer, frame: *const Frame) !void {
        try frame.print_prefix(writer);
        try writer.print("{s}  id={d}, size={d}\n", .{ file.name, file.id, file.size });
    }
};

const Folder = struct {
    id: ID,
    name: []const u8,
    children: []const Folder,

    fn deinit(folder: *const Folder, allocator: Allocator) void {
        for (folder.children) |child| {
            child.deinit(allocator);
        }
        allocator.free(folder.name);
        allocator.free(folder.children);
    }

    fn render(
        folder: *const Folder,
        writer: *Io.Writer,
        files_by_parent: *const std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(File)),
        frame: *const Frame,
    ) !void {
        try frame.print_prefix(writer);
        try writer.print("{s}\n", .{folder.name});

        const files = files_by_parent.get(folder.id) orelse std.ArrayListUnmanaged(File).empty;
        const num_files = files.items.len;
        const num_children = folder.children.len;
        for (folder.children, 0..) |*child, idx| {
            const child_frame: Frame = .{
                .parent = frame,
                .last = idx + 1 == num_children and num_files == 0,
            };
            try child.render(writer, files_by_parent, &child_frame);
        }

        for (files.items, 0..) |*file, idx| {
            const file_frame: Frame = .{
                .parent = frame,
                .last = idx + 1 == num_files,
            };
            try file.render(writer, &file_frame);
        }
    }
};

const Frame = struct {
    parent: ?*const Frame,
    last: bool,

    fn print_prefix_inner(frame: *const Frame, writer: *Io.Writer) !void {
        const parent = frame.parent orelse return;
        if (parent.parent != null) {
            try parent.print_prefix_inner(writer);
            try writer.writeAll(if (parent.last) bar_blank else bar_vertical);
        }
    }

    fn print_prefix(frame: *const Frame, writer: *Io.Writer) !void {
        try frame.print_prefix_inner(writer);
        if (frame.parent != null) {
            try writer.writeAll(if (frame.last) elbow_last else elbow_mid);
        }
    }
};

pub const Listing = struct {
    folders: []const Folder,
    files: []const File,

    fn deinit(listing: *const Listing, allocator: Allocator) void {
        for (listing.folders) |*folder| {
            folder.deinit(allocator);
        }
        for (listing.files) |*file| {
            file.deinit(allocator);
        }
        allocator.free(listing.folders);
        allocator.free(listing.files);
    }

    fn render(listing: *const Listing, writer: *Io.Writer, allocator: Allocator) !void {
        // Group files by parent_id so each folder renders its files in O(1).
        var files_by_parent: std.AutoHashMapUnmanaged(ID, std.ArrayListUnmanaged(File)) = .empty;
        for (listing.files) |*file| {
            const get_or_put = try files_by_parent.getOrPut(allocator, file.parent_id);
            if (get_or_put.found_existing) {
                // The file list for this parent already exists; the append below reuses it.
            } else {
                get_or_put.value_ptr.* = .empty;
            }
            try get_or_put.value_ptr.append(allocator, file.*);
        }
        defer {
            var it = files_by_parent.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            files_by_parent.deinit(allocator);
        }

        var folder_ids: std.AutoHashMapUnmanaged(ID, void) = .empty;
        defer folder_ids.deinit(allocator);
        for (listing.folders) |*folder| {
            try collect_folder_ids(&folder_ids, allocator, folder);
        }

        for (listing.folders) |*folder| {
            const frame: Frame = .{ .parent = null, .last = true };
            try folder.render(writer, &files_by_parent, &frame);
        }

        // Render orphaned files at the root level.
        for (listing.files) |*file| {
            if (folder_ids.contains(file.parent_id)) {
                continue;
            }
            const frame: Frame = .{ .parent = null, .last = true };
            try file.render(writer, &frame);
        }
    }
};

fn collect_folder_ids(
    folder_ids: *std.AutoHashMapUnmanaged(ID, void),
    allocator: Allocator,
    folder: *const Folder,
) !void {
    try folder_ids.put(allocator, folder.id, {});
    for (folder.children) |*child| {
        try collect_folder_ids(folder_ids, allocator, child);
    }
}

// AI-generated bs for testing
fn fixture(allocator: Allocator) !Listing {
    var readings = LIBMTP_folder_t{
        .folder_id = 3,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Readings"),
        .sibling = null,
        .child = null,
    };
    var periodicals = LIBMTP_folder_t{
        .folder_id = 5,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Periodicals"),
        .sibling = null,
        .child = null,
    };
    var books = LIBMTP_folder_t{
        .folder_id = 2,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Books"),
        .sibling = &periodicals,
        .child = &readings,
    };
    var albums = LIBMTP_folder_t{
        .folder_id = 6,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Albums"),
        .sibling = null,
        .child = null,
    };
    var music = LIBMTP_folder_t{
        .folder_id = 4,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Music"),
        .sibling = null,
        .child = &albums,
    };
    var kindle = LIBMTP_folder_t{
        .folder_id = 1,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Kindle"),
        .sibling = &music,
        .child = &books,
    };

    var f107 = LIBMTP_file_t{
        .item_id = 107,
        .parent_id = 999,
        .storage_id = 0,
        .filename = @constCast("mystery.dat"),
        .filesize = 1,
        .modificationdate = 0,
        .filetype = 0,
        .next = null,
    };
    var f106 = LIBMTP_file_t{
        .item_id = 106,
        .parent_id = 0,
        .storage_id = 0,
        .filename = @constCast("notes.txt"),
        .filesize = 64,
        .modificationdate = 0,
        .filetype = 0,
        .next = &f107,
    };
    var f105 = LIBMTP_file_t{
        .item_id = 105,
        .parent_id = 6,
        .storage_id = 0,
        .filename = @constCast("album.flac"),
        .filesize = 65536,
        .modificationdate = 0,
        .filetype = 0,
        .next = &f106,
    };
    var f104 = LIBMTP_file_t{
        .item_id = 104,
        .parent_id = 4,
        .storage_id = 0,
        .filename = @constCast("track.mp3"),
        .filesize = 8192,
        .modificationdate = 0,
        .filetype = 0,
        .next = &f105,
    };
    var f103 = LIBMTP_file_t{
        .item_id = 103,
        .parent_id = 5,
        .storage_id = 0,
        .filename = @constCast("mag.pdf"),
        .filesize = 3072,
        .modificationdate = 0,
        .filetype = 0,
        .next = &f104,
    };
    var f102 = LIBMTP_file_t{
        .item_id = 102,
        .parent_id = 3,
        .storage_id = 0,
        .filename = @constCast("reading.txt"),
        .filesize = 512,
        .modificationdate = 0,
        .filetype = 0,
        .next = &f103,
    };
    var f101 = LIBMTP_file_t{
        .item_id = 101,
        .parent_id = 2,
        .storage_id = 0,
        .filename = @constCast("book.pdf"),
        .filesize = 2048,
        .modificationdate = 0,
        .filetype = 0,
        .next = &f102,
    };
    var f100 = LIBMTP_file_t{
        .item_id = 100,
        .parent_id = 1,
        .storage_id = 0,
        .filename = @constCast("cover.png"),
        .filesize = 1024,
        .modificationdate = 0,
        .filetype = 0,
        .next = &f101,
    };

    return snapshot(allocator, &kindle, &f100, 10);
}

test "fixture has the expected structure" {
    const a = std.testing.allocator;

    var listing = try fixture(a);
    defer listing.deinit(a);

    try std.testing.expectEqual(@as(usize, 2), listing.folders.len);
    try std.testing.expectEqualStrings("Kindle", listing.folders[0].name);
    try std.testing.expectEqual(@as(u32, 1), listing.folders[0].id);
    try std.testing.expectEqual(@as(usize, 2), listing.folders[0].children.len);
    try std.testing.expectEqualStrings("Readings", listing.folders[0].children[0].children[0].name);
    try std.testing.expectEqualStrings("Albums", listing.folders[1].children[0].name);
    try std.testing.expectEqual(@as(usize, 8), listing.files.len);
    try std.testing.expectEqual(@as(u32, 100), listing.files[0].id);
    try std.testing.expectEqual(@as(u32, 2), listing.files[1].parent_id);
    try std.testing.expectEqual(@as(u32, 0), listing.files[6].parent_id);
    try std.testing.expectEqual(@as(u32, 999), listing.files[7].parent_id);
}

test "fixture without deinit detected as leaks" {
    var safe = std.heap.SafeAllocator.init(std.heap.page_allocator, .{});
    var counted = std.testing.FailingAllocator.init(safe.allocator(), .{});

    _ = try fixture(counted.allocator());

    try std.testing.expect(safe.deinitLog(false) > 0);
}

test "fixture deinit frees everything" {
    var safe = std.heap.SafeAllocator.init(std.heap.page_allocator, .{});
    var counted = std.testing.FailingAllocator.init(safe.allocator(), .{});

    var listing = try fixture(counted.allocator());
    listing.deinit(counted.allocator());

    try std.testing.expectEqual(@as(usize, 0), safe.deinitLog(false));
}

test "render produces the expected tree" {
    const a = std.testing.allocator;
    var listing = try fixture(a);
    defer listing.deinit(a);

    var writer = Io.Writer.Allocating.init(a);
    try listing.render(&writer.writer, a);
    const rendered = try writer.toOwnedSlice();
    defer a.free(rendered);

    // Kindle
    // ├─ Books
    // │  ├─ Readings
    // │  │  └─ reading.txt  id=102, size=512
    // │  └─ book.pdf  id=101, size=2048
    // ├─ Periodicals
    // │  └─ mag.pdf  id=103, size=3072
    // └─ cover.png  id=100, size=1024
    // Music
    // ├─ Albums
    // │  └─ album.flac  id=105, size=65536
    // └─ track.mp3  id=104, size=8192
    // notes.txt  id=106, size=64
    // mystery.dat  id=107, size=1
    try std.testing.expectEqualStrings(
        "Kindle\n" ++
            elbow_mid ++ "Books\n" ++
            bar_vertical ++ elbow_mid ++ "Readings\n" ++
            bar_vertical ++ bar_vertical ++ elbow_last ++ "reading.txt  id=102, size=512\n" ++
            bar_vertical ++ elbow_last ++ "book.pdf  id=101, size=2048\n" ++
            elbow_mid ++ "Periodicals\n" ++
            bar_vertical ++ elbow_last ++ "mag.pdf  id=103, size=3072\n" ++
            elbow_last ++ "cover.png  id=100, size=1024\n" ++
            "Music\n" ++
            elbow_mid ++ "Albums\n" ++
            bar_vertical ++ elbow_last ++ "album.flac  id=105, size=65536\n" ++
            elbow_last ++ "track.mp3  id=104, size=8192\n" ++
            "notes.txt  id=106, size=64\n" ++
            "mystery.dat  id=107, size=1\n",
        rendered,
    );
}

test "snapshot with null inputs" {
    const a = std.testing.allocator;
    const listing = try snapshot(a, null, null, 233);
    defer listing.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), listing.folders.len);
    try std.testing.expectEqual(@as(usize, 0), listing.files.len);
}

test "snapshot rejects folders beyond max_depth" {
    const a = std.testing.allocator;

    // Kindle(0) -> Books(1) -> Readings(2)
    var readings = LIBMTP_folder_t{
        .folder_id = 3,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Readings"),
        .sibling = null,
        .child = null,
    };
    var books = LIBMTP_folder_t{
        .folder_id = 2,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Books"),
        .sibling = null,
        .child = &readings,
    };
    var kindle = LIBMTP_folder_t{
        .folder_id = 1,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Kindle"),
        .sibling = null,
        .child = &books,
    };

    try std.testing.expectError(error.NestingTooDeep, snapshot(a, &kindle, null, 1));

    const listing = try snapshot(a, &kindle, null, 2);
    defer listing.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), listing.folders.len);
    try std.testing.expectEqual(@as(usize, 1), listing.folders[0].children.len);
}

test "snapshot bounds cyclic folder trees" {
    const a = std.testing.allocator;

    var loop = LIBMTP_folder_t{
        .folder_id = 9,
        .parent_id = 0,
        .storage_id = 0,
        .name = @constCast("Loop"),
        .sibling = null,
        .child = null,
    };
    loop.child = &loop;

    try std.testing.expectError(error.NestingTooDeep, snapshot(a, &loop, null, 100));
}
