const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const VERSION: []const u8 = "1.0.0";

const FILE_NAME_LENGTH = 32;


var error_buffer: [6 * 1024]u8 = undefined;
var print_buffer: [6 * 1024]u8 = undefined;

const Options = enum { UNKNOWN, STATUS, CHECKOUT, DELETE, HELP };
const Config = struct {
    has_git_folder: bool = false,
    has_rotate_folder: bool = false,
    is_symlink: bool = false,
    unknown_is_a_git_repo: bool = false,
};

const RotateRecord = extern struct {
    current: [FILE_NAME_LENGTH]u8,

    fn renameCurrentRecord(self: *RotateRecord, record: ?*[]const u8) void {
        @memcpy(self.current[0..], &empty);
        if (record != null) {
            var r = record.?;
            @memcpy(self.current[0..r.len], r.*);
            r = undefined;
        }
    }
};

const empty: [32]u8 = @splat(0);

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        try printHelp(io);
        return;
    }

    var config: Config = .{};
    const cwd = std.Io.Dir.cwd();
    {
        var dir = try cwd.openDir(io, ".", .{ .iterate = true });
        defer dir.close(io);
        var cwd_walker = dir.iterate();

        // finding the git and gitswap directories
        while (cwd_walker.next(io)) |item_or_null| {
            if (item_or_null == null) break;
            const item = item_or_null.?;

            if (config.has_git_folder and config.has_rotate_folder) break;
            if (item.kind != .directory and item.kind != .sym_link) continue;

            if (std.mem.eql(u8, ".git", item.name)) {
                config.has_git_folder = true;
                if (item.kind == .sym_link) config.is_symlink = true;
            }
            if (std.mem.eql(u8, ".gitrotate", item.name)) {
                config.has_rotate_folder = true;
            }
        } else |err| {
            logError(io, arena, err, "failure accessing directory");
            return;
        }
    }

    const option_str: []const u8 = try gpa.dupe(u8, args[1]);
    defer gpa.free(option_str);

    const option_case_str = try std.ascii.allocUpperString(arena, option_str);
    const option = std.meta.stringToEnum(Options, option_case_str) orelse Options.UNKNOWN;

    var git_repos_array : std.ArrayListUnmanaged([]const u8)  = .empty;
    defer git_repos_array.deinit(arena);

    if (option == Options.HELP) {
        try printHelp(io);
        return;
    }

    if (!config.has_rotate_folder and
        !config.has_git_folder){
        logError(io, arena, error.InvalidGitRepo, "this is not a git repository");
        return;
    }

    if (!config.has_rotate_folder){
        cwd.createDir(io, ".gitrotate", std.Io.File.Permissions.default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    {
        var dir = try cwd.openDir(io, "./.gitrotate/", .{ .iterate = true });
        defer dir.close(io);
        var dir_iter = dir.iterate();

        while (dir_iter.next(io)) |entry| {
                if (entry == null) break;
                if (entry.?.kind != .directory) continue;

                if (option == .UNKNOWN and std.mem.eql(u8, entry.?.name, option_str)) {
                    config.unknown_is_a_git_repo = true;
                }

                git_repos_array.append(arena, entry.?.name) catch |err| {
                    logError(io, arena, err, "OUT OF MEMORY");
                    return;
                };
        }  else |err| {
            logError(io, arena, err, "failure accessing directory");
            return;
        }

        if (option == Options.UNKNOWN and !config.unknown_is_a_git_repo) {
            logError(io, arena, error.InvalidCommand, "unknown command or git record");
            try printHelp(io);
            return;
        }

        const git_repos = try git_repos_array.toOwnedSlice(arena);

        // create the .RECORDS file if it doesn't exist
        var record_file = try cwd.createFile(io, "./.gitrotate/.RECORDS", .{ .read = true, .truncate = false });
        record_file.close(io);

        var read_buffer: [1024]u8 = undefined;
        // var write_buffer: [1024]u8 = undefined;
        var rotate_record = ReadRotateRecord(io, cwd, &read_buffer);

        // label: 
        switch(option){
            .STATUS => {
                for (git_repos) |repo| {
                    var file_name: [32]u8 = @splat(0);
                    @memcpy(file_name[0..repo.len], repo);
                    const prefix: []const u8 = if (std.mem.eql(u8, &file_name, rotate_record.current[0..])) " * " else "   ";
                    const msg = try std.fmt.allocPrint(arena, "{s}{s}", .{ prefix, repo });
                    defer arena.free(msg);
                    try print(io, msg);
                }
            },
            .UNKNOWN => {

            },
            .CHECKOUT => {},
            .DELETE => {},
            .HELP => unreachable,

        }

    }
}


fn logError(io: Io, arena: std.mem.Allocator, err: anyerror, message: []const u8) void {
    var writer = Io.File.stderr().writer(io, &error_buffer);
    const parsed_msg = std.fmt.allocPrint(arena, "! GIT Rotate - ERROR < {s} >: {s}\n\n", .{@errorName(err), message}) catch "! GIT Rotate - ERROR <OutOfMemory>: OUT OF MEMORY\n";
    writer.interface.writeAll(parsed_msg) catch {};
    writer.flush() catch {};
}


fn printHelp(io: Io) !void {
    var writer = Io.File.stdout().writer(io, &print_buffer);
    try writer.interface.writeAll(
        "GIT Rotate - A simple git management tool\n" ++
            "Version: " ++ VERSION ++ "\n" ++
            "Usage: rotate <command> [options]\n" ++
            "Commands:\n" ++
            "  <record> - Swap to a git record with the specified name\n" ++
            "  status - Show the current status\n" ++
            "  checkout <record> - Register a new record\n" ++
            "  delete <record> - Delete a record\n" ++
            "  help - Show this help message\n",
    );
    try writer.flush();
}

fn print(io: Io, message: []const u8) !void {
    var writer = Io.File.stdout().writer(io, &print_buffer);
    try writer.interface.writeAll(message);
    try writer.flush();
}

fn ReadRotateRecord(io: Io, cwd: Io.Dir, buffer: *[1024]u8) RotateRecord {
    var records = cwd.openFile(io, "./.gitrotate/.RECORDS", .{
        .mode = .read_only,
    }) catch {
        return RotateRecord{ .current = empty };
    };
    defer records.close(io);

    var reader = records.reader(io, buffer);
    return reader.interface.takeStruct(RotateRecord, .little) catch RotateRecord{ .current = empty };
}

fn WriteRotateRecord(io: Io, cwd: Io.Dir, buffer: *[1024]u8, rotate_record: RotateRecord) !void {
    var records = try cwd.openFile(io, "./.gitrotate/.RECORDS", .{
        .mode = .write_only,
    });
    defer records.close(io);
    var writer = records.writer(io, buffer);
    try writer.interface.writeStruct(rotate_record, .little);
    try writer.flush();
}

