const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

// create swap_id
// checkout
// list
// checkout swap_id
// NOTE: before swap make sure there is nothing to or commit

const FILE_NAME_LENGTH = 32;
const help: []const u8 =
    \\COMMANDS:
    \\  checkout <swap_id> [optional <git origin> <git repo>] : swap an existing git to git with the repo id if none exists creates a new one
    \\  list : list all existing swaps 
    \\  record <swap_id>: create a record of your current .git folder
    \\  delete <swap_id>: deletes record of your .git folder with the swap_id
    \\  help: shows this help message  
;
const Options = enum { RECORD, LIST, CHECKOUT, DELETE, HELP };

const SwapRecord = extern struct {
    current: [FILE_NAME_LENGTH]u8,

    fn renameCurrentRecord(self: *SwapRecord, record: ?*[]const u8) void {
        @memcpy(self.current[0..], &empty);
        if (record != null){
            var r = record.?;
            @memcpy(self.current[0..r.len], r.*);
            r = undefined;
        }
    }
};

const empty: [32]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        //  error show help list
        std.debug.print("Error: invalid args provided\n\ngit swap <command> \n{s}", .{help});
        return;
    }
    const option_str: []const u8 = try arena.dupe(u8, args[1]);
    defer arena.free(option_str);

    const option_case_str = try std.ascii.allocUpperString(arena, option_str);
    const option = std.meta.stringToEnum(Options, option_case_str) orelse Options.HELP;

    const cwd = std.Io.Dir.cwd();
    var has_git = false;
    var has_swap: bool = false;
    var git_is_symlink = false;
    {
        var dir = try cwd.openDir(io, ".", .{ .iterate = true });
        defer dir.close(io);
        var cwd_walker = dir.iterate();

        while (cwd_walker.next(io)) |item_or_null| {
            if (item_or_null == null) break;
            if (has_git and has_swap) break;
            if (item_or_null.?.kind != .directory and item_or_null.?.kind != .sym_link) continue;
            const item = item_or_null.?;

            if (std.mem.eql(u8, ".git", item.name)) {
                has_git = true;
                if (item.kind == .sym_link) git_is_symlink = true;
            }
            if (std.mem.eql(u8, ".gitswap", item.name)) {
                has_swap = true;
            }
        } else |err| {
            std.debug.print("Error: {any}\n\n", .{err});
        }
    }

    if (!has_git and !has_swap) {
        std.debug.print("Error: this is not a git repository\n\n", .{});
        return;
    }

    if (!has_swap) {
        cwd.createDir(io, ".gitswap", std.Io.File.Permissions.default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    var records = try cwd.createFile(io, "./.gitswap/.RECORDS", .{ .read = true, .truncate = false });
    records.close(io);

    var read_buffer: [1024]u8 = undefined;
    var write_buffer: [1024]u8 = undefined;
    var swap_record = ReadSwapRecord(io, cwd, &read_buffer);

    label: switch (option) {
        .RECORD => {
            if (has_git and git_is_symlink) {
                std.debug.print("Invalid git repository \nnote:you might already be in a switch record", .{});
                return;
            }
            if (args.len < 2) {
                std.debug.print("Error: required args\ngit swap record {s}", .{help});
                return;
            }
            var swap_id: []const u8 = try arena.dupe(u8, args[2]);
            defer arena.free(swap_id);
            if (swap_id.len > FILE_NAME_LENGTH) {
                std.debug.print("Error: Swap Id too long", .{});
                return;
            }
            if (has_folder(io, cwd, "./.gitswap", swap_id)) {
                std.debug.print("Error: record id already exist", .{});
                return;
            }
            if (!std.mem.eql(u8, &swap_record.current, &empty) and has_git and git_is_symlink) {
                std.debug.print("Error: record already exist as {s}", .{swap_record.current});
                return;
            }
            const new_path = try std.fmt.allocPrint(gpa, "./.gitswap/{s}/", .{swap_id});
            defer gpa.free(new_path);
            try cwd.createDir(io, new_path, std.Io.File.Permissions.default_dir);
            cwd.rename("./.git", cwd, new_path, io) catch {
                std.debug.print("Invalid git repository \nnote:you might already be in a switch record", .{});
                return;
            };
            try cwd.symLink(io, new_path, "./.git", .{ .is_directory = true });

            swap_record.renameCurrentRecord(&swap_id);
            try WriteSwapRecord(io, cwd, &write_buffer, swap_record);
        },

        .CHECKOUT => {
            if (has_git and !git_is_symlink) {
                std.debug.print("Error: current git repository has no swap record\nrun 'git swap record <swap id>' instead or use help \n\n{s}", .{help});
                return;
            }

            if (args.len < 2) {
                std.debug.print("Error: required args\ngit swap record {s}", .{help});
                return;
            }
            var swap_id: []const u8 = try arena.dupe(u8, args[2]);
            defer arena.free(swap_id);
            if (swap_id.len > FILE_NAME_LENGTH) {
                std.debug.print("Error: Swap Id too long", .{});
                return;
            }

            cwd.deleteDir(io, "./.git/") catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
            if (!has_folder(io, cwd, "./.gitswap", swap_id)) {
                std.debug.print("Id not found creating new Swap", .{});
                var results = try std.process.run(arena, io, .{
                    .argv = &.{ "git", "init" },
                });

                std.debug.print("{s} ", .{ results.stdout });
                checkTerminationState(&results) catch {
                    return;
                };

                if (args.len > 2){
                    var origin: []const u8 = undefined;
                    var repo: []const u8 = undefined;
                    if (args.len >= 4){
                        origin = try arena.dupe(u8, args[3]);
                        repo = try arena.dupe(u8, args[4]);
                    } else if (args.len >= 3){  
                        origin = try arena.dupe(u8, "origin");
                        repo = try arena.dupe(u8, args[4]);
                    }


                    const git_cmd: []const u8 = try std.fmt.allocPrint(arena, "git remote add {s} {s} && git fetch {s}", .{origin, repo, origin});
                    defer arena.free(git_cmd);
                    const sys_argv = switch (builtin.os.tag) {
                        .windows => [_][]const u8{ "cmd.exe", "/c", git_cmd },
                        else => [_][]const u8{ "sh", "-c", git_cmd },
                    };
                    var sys_result = try std.process.run(arena, io, .{
                        .argv = &sys_argv,
                    });

                    std.debug.print("{s} ", .{ sys_result.stdout });
                    checkTerminationState(&sys_result) catch {
                        return;
                    };
                }

                std.debug.print("\nINFO: to avoid conflict revert to your last local commit\nUSING: git reset <starting-commit-sha>\n", .{});
                git_is_symlink = false;
                continue :label Options.RECORD;
            } else {
                const new_path = try std.fmt.allocPrint(gpa, "./.gitswap/{s}/", .{swap_id});
                defer gpa.free(new_path);
                try cwd.symLink(io, new_path, "./.git", .{ .is_directory = true });
                swap_record.renameCurrentRecord(&swap_id);
                try WriteSwapRecord(io, cwd, &write_buffer, swap_record);
            }
            return;
        },
        // delete a swap record
        // note: doing this is at your discretion
        .DELETE => {
            if (args.len < 2) {
                std.debug.print("Error: required args\ngit swap record {s}", .{help});
                return;
            }
            const swap_id: []const u8 = try arena.dupe(u8, args[2]);
            defer arena.free(swap_id);
            if (has_folder(io, cwd, "./.gitswap", swap_id)) {
                const new_path = try std.fmt.allocPrint(gpa, "./.gitswap/{s}/", .{swap_id});
                defer gpa.free(new_path);
                try cwd.deleteTree(io, new_path);

                var file_name: [32]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
                @memcpy(file_name[0..swap_id.len], swap_id);
                if (std.mem.eql(u8, &file_name, &swap_record.current)) {
                    swap_record.renameCurrentRecord(null);
                    try WriteSwapRecord(io, cwd, &write_buffer, swap_record);
                    try cwd.deleteDir(io, "./.git/");
                }
            } else {
                std.debug.print("Error: {s} record not found", .{swap_id});
                return;
            }
        },
        // list all the .swap records available and if the current git is not part of a swap
        .LIST => {
            var dir = try cwd.openDir(io, "./.gitswap/", .{ .iterate = true });
            defer dir.close(io);
            var dir_iter = dir.iterate();
            if (std.mem.eql(u8, &empty, &swap_record.current)) {
                std.debug.print("* .git <not recorded>\n", .{});
            }
            while (dir_iter.next(io)) |entry| {
                if (entry == null) break;
                if (entry.?.kind != .directory) continue;

                var file_name: [32]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
                @memcpy(file_name[0..entry.?.name.len], entry.?.name);
                if (std.mem.eql(u8, &file_name, &swap_record.current)) {
                    std.debug.print("* {s}\n", .{entry.?.name});
                } else {
                    std.debug.print("{s}\n", .{entry.?.name});
                }
            } else |err| {
                std.debug.print("Error: {}", .{err});
                return;
            }
        },
        .HELP => {
            std.debug.print("GIT SWAP HELP\n{s}", .{help});
            return;
        },
    }

    // std.debug.print("{any}", .{cwd});
}

fn WriteSwapRecord(io: Io, cwd: Io.Dir, buffer: *[1024]u8, swap_record: SwapRecord) !void {
    var records = try cwd.openFile(io, "./.gitswap/.RECORDS", .{
        .mode = .write_only,
    });
    defer records.close(io);
    var writer = records.writer(io, buffer);
    try writer.interface.writeStruct(swap_record, .little);
    try writer.flush();
}

fn ReadSwapRecord(io: Io, cwd: Io.Dir, buffer: *[1024]u8) SwapRecord {
    var records = cwd.openFile(io, "./.gitswap/.RECORDS", .{
        .mode = .read_only,
    }) catch {
        return SwapRecord{ .current = empty };
    };
    defer records.close(io);

    var reader = records.reader(io, buffer);
    return reader.interface.takeStruct(SwapRecord, .little) catch SwapRecord{ .current = empty };
}

fn has_folder(io: Io, cwd: std.Io.Dir, path: []const u8, folder_to_check: []const u8) bool {
    var dir = cwd.openDir(io, path, .{ .iterate = true }) catch {
        return false;
    };
    defer dir.close(io);
    var cwd_walker = dir.iterate();
    while (cwd_walker.next(io)) |file| {
        if (file == null) break;
        if (file.?.kind != .directory) continue;

        if (std.mem.eql(u8, folder_to_check, file.?.name)) {
            return true;
        }
    } else |_| {
        return false;
    }
    return false;
}

fn checkTerminationState(result: *std.process.RunResult) !void {
    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("Process failed with non-zero exit code: {d}\n", .{code});
                std.debug.print("Stderr: {s}\n", .{result.stderr});
                return error.ProcessFailed;
            }
            std.debug.print("Process succeeded!\n", .{});
        },
        .signal => |sig| {
            std.debug.print("Process was killed by signal: {d}\n", .{sig});
            return error.ProcessKilledBySignal;
        },
        .stopped => |sig| {
            std.debug.print("Process was stopped by signal: {d}\n", .{sig});
            return error.ProcessStopped;
        },
        .unknown => |code| {
            std.debug.print("Process terminated abnormally with code: {d}\n", .{code});
            return error.ProcessUnknownFailure;
        },
    }
}