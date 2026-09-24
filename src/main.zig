/// Git Rotate
/// Copyright (c) 2026 Owor Patrick Ikongha
/// SPDX-License-Identifier: MIT
///
/// Author: Owor Patrick Ikongha <oworpatrickikongha@gmail.com>

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

const HasFolderStruct = struct {
    git_repos: []const []const u8,

    pub fn hasFolder(self: HasFolderStruct, folder_name: []const u8) bool {
        for (self.git_repos) |repo| {
            if (std.mem.eql(u8, repo, folder_name)) return true;
        }
        return false;
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

    var git_repos_array: std.ArrayListUnmanaged([]const u8) = .empty;
    defer git_repos_array.deinit(arena);

    if (option == Options.HELP) {
        try printHelp(io);
        return;
    }

    const remote_repo_intl = option == Options.CHECKOUT and args.len >= 4;

    if ((option != Options.CHECKOUT or !remote_repo_intl) and !config.has_rotate_folder and
        !config.has_git_folder)
    {
        return logError(io, arena, error.InvalidGitRepo, "this is not a git repository");
    }

    if (!config.has_rotate_folder) {
        cwd.createDir(io, ".gitrotate", std.Io.File.Permissions.default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return logError(io, arena, err, "failure creating .gitrotate directory");
        };
    }

    // TODO: check if .gitignore contains .gitrotate or .gitrotate file and append if it doesnt
    upsertGitIgnore(io, cwd, arena) catch |err| {
        return logError(io, arena, err, "failure updating .gitignore file");
    };

    // find .gitrotate in the gitignore file and append it if it doesn't exist

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
                return logError(io, arena, err, "OUT OF MEMORY");
            };
        } else |err| {
            return logError(io, arena, err, "failure accessing directory");
        }

        if (option == Options.UNKNOWN and !config.unknown_is_a_git_repo) {
            logError(io, arena, error.InvalidCommand, "unknown command or git record");
            return try printHelp(io);
        }

        const git_repos = git_repos_array.toOwnedSlice(arena) catch |err| {
            return logError(io, arena, err, "OUT OF MEMORY");
        };

        // create the .RECORDS file if it doesn't exist
        var record_file = try cwd.createFile(io, "./.gitrotate/.RECORDS", .{ .read = true, .truncate = false });
        record_file.close(io);

        var read_buffer: [1024]u8 = undefined;
        var write_buffer: [1024]u8 = undefined;
        var rotate_record = ReadRotateRecord(io, cwd, &read_buffer);

        const HS = HasFolderStruct{ .git_repos = git_repos };

        // label:
        switch (option) {
            .STATUS => {
                for (git_repos) |repo| {
                    var file_name: [32]u8 = @splat(0);
                    @memcpy(file_name[0..repo.len], repo);
                    const prefix: []const u8 = if (std.mem.eql(u8, &file_name, rotate_record.current[0..])) " * " else "   ";
                    const msg = try std.fmt.allocPrint(arena, "{s}{s}\n", .{ prefix, repo });
                    defer arena.free(msg);
                    try print(io, msg);
                }
            },
            .UNKNOWN => {
                if (config.has_git_folder and !config.is_symlink) {
                    return logError(io, arena, error.InvalidGitRepo, "please checkout your current git repository using git rotate to continue");
                }
                var rotate_id: []const u8 = try arena.dupe(u8, args[1]);
                defer arena.free(rotate_id);
                if (rotate_id.len > FILE_NAME_LENGTH) {
                    logError(io, arena, error.InvalidCommand, "git record name is too long");
                    return;
                }
                cwd.deleteDir(io, "./.git/") catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => return logError(io, arena, err, "failure deleting git directory"),
                };

                if (!HS.hasFolder(rotate_id)) {
                    return logError(io, arena, error.InvalidCommand, "git record does not exist");
                } else {
                    const new_path = try std.fmt.allocPrint(arena, "./.gitrotate/{s}/", .{rotate_id});
                    defer arena.free(new_path);
                    try cwd.symLink(io, new_path, "./.git", .{ .is_directory = true });
                    rotate_record.renameCurrentRecord(&rotate_id);
                    WriteRotateRecord(io, cwd, &read_buffer, rotate_record) catch |err| {
                        return logError(io, arena, err, "failure updating RECORD");
                    };
                    return;
                }
            },
            .CHECKOUT => {
                if (args.len < 3) {
                    return logError(io, arena, error.InvalidCommand, "missing record name for the git repository");
                }

                var rotate_id: []const u8 = try arena.dupe(u8, args[2]);
                defer arena.free(rotate_id);
                if (rotate_id.len > FILE_NAME_LENGTH) {
                    return logError(io, arena, error.InvalidCommand, "git record name is too long");
                }
                if (HS.hasFolder(rotate_id)) {
                    return logError(io, arena, error.InvalidCommand, "git record name already exists select another name");
                }

                if (remote_repo_intl) {
                    if (config.has_git_folder and !config.is_symlink) {
                        return logError(io, arena, error.LocalRepoFound, "Local repository found manually set your remote, and checkout rotate with only the suggested record name");
                    } else if (config.has_git_folder and config.is_symlink) {
                        // delete the current symlink and create a new one with the new remote
                        cwd.deleteDir(io, "./.git/") catch |err| switch (err) {
                            error.FileNotFound => {},
                            else => return logError(io, arena, err, "failure deleting git directory"),
                        };
                        config.is_symlink = false;
                    }

                    var origin: []const u8 = undefined;
                    var repo: []const u8 = undefined;

                    if (args.len >= 5) {
                        origin = try arena.dupe(u8, args[3]);
                        repo = try arena.dupe(u8, args[4]);
                    } else if (args.len >= 4) {
                        origin = try arena.dupe(u8, "origin");
                        repo = try arena.dupe(u8, args[3]);
                    }
                    defer arena.free(origin);
                    defer arena.free(repo);

                    var results = try std.process.run(arena, io, .{
                        .argv = &.{ "git", "init" },
                    });
                    print(io, results.stdout) catch {};
                    checkTerminationState(&results) catch {
                        return;
                    };

                    if (!std.mem.eql(u8, repo, "local")) {
                        const git_cmd: []const u8 = try std.fmt.allocPrint(arena, "git remote add {s} {s} && git fetch {s}", .{ origin, repo, origin });
                        defer arena.free(git_cmd);
                        const sys_argv = switch (builtin.os.tag) {
                            .windows => [_][]const u8{ "cmd.exe", "/c", git_cmd },
                            else => [_][]const u8{ "sh", "-c", git_cmd },
                        };
                        var sys_result = try std.process.run(arena, io, .{
                            .argv = &sys_argv,
                        });
                        print(io, sys_result.stdout) catch {};
                        checkTerminationState(&sys_result) catch |err| {
                            return logError(io, arena, err, "failure executing git command");
                        };
                    }
                }

                if (config.has_git_folder and config.is_symlink) {
                    return logError(io, arena, error.GitIsAlreadyInRecord, "Current Repository is Already Recorded For Rotation");
                }

                const new_path = try std.fmt.allocPrint(arena, "./.gitrotate/{s}/", .{rotate_id});
                defer arena.free(new_path);

                cwd.createDir(io, new_path, std.Io.File.Permissions.default_dir) catch |err| {
                    return logError(io, arena, err, "failure creating git record");
                };

                cwd.rename("./.git", cwd, new_path, io) catch |err| {
                    return logError(io, arena, err, "failure creating a git record, this might happen because you are already in a git record or having file permission issues");
                };
                cwd.symLink(io, new_path, "./.git", .{ .is_directory = true }) catch |err| {
                    return logError(io, arena, err, "failure creating a git record, this might happen because you are already in a git record or having file permission issues");
                };

                rotate_record.renameCurrentRecord(&rotate_id);
                try WriteRotateRecord(io, cwd, &write_buffer, rotate_record);
            },
            .DELETE => {
                if (args.len < 3) {
                    return logError(io, arena, error.InvalidCommand, "missing git record name");
                }
                const rotate_id: []const u8 = try arena.dupe(u8, args[2]);
                defer arena.free(rotate_id);
                if (HS.hasFolder(rotate_id)) {
                    const new_path = try std.fmt.allocPrint(gpa, "./.gitswap/{s}/", .{rotate_id});
                    defer gpa.free(new_path);
                    cwd.deleteTree(io, new_path) catch |err| {
                        return logError(io, arena, err, "failure deleting git record");
                    };
                    var file_name: [32]u8 = @splat(0);
                    @memcpy(file_name[0..rotate_id.len], rotate_id);
                    if (std.mem.eql(u8, &file_name, &rotate_record.current)) {
                        rotate_record.renameCurrentRecord(null);
                        try WriteRotateRecord(io, cwd, &write_buffer, rotate_record);
                        try cwd.deleteDir(io, "./.git/");
                    }
                }
                return;
            },
            .HELP => unreachable,
        }
    }
}

fn logError(io: Io, arena: std.mem.Allocator, err: anyerror, message: []const u8) void {
    var writer = Io.File.stderr().writer(io, &error_buffer);
    const parsed_msg = std.fmt.allocPrint(arena, "! GIT Rotate - ERROR < {s} >: {s}\n\n", .{ @errorName(err), message }) catch "! GIT Rotate - ERROR <OutOfMemory>: OUT OF MEMORY\n";
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
            "  <record name> - Swap to a git record with the specified name\n" ++
            "  status   - Show the current status\n" ++
            "  checkout - Register a new record\n" ++
            "             when the specified git origin and remote URL are provided\n" ++
            "             it will be used to initialize the record if the remote is\n" ++
            "             set to local it creates a new local repository\n" ++ "             usage: checkout <record name> [optional <git origin> <git remote url | local>]\n" ++
            "  delete   - Delete a record\n             usage: delete <record name>\n" ++
            "  help     - Show this help message\n",
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

fn checkTerminationState(result: *std.process.RunResult) !void {
    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("Process failed with non-zero exit code: {d}\n", .{code});
                std.debug.print("Stderr: {s}\n", .{result.stderr});
                return error.ProcessFailed;
            }
            // std.debug.print("Process succeeded!\n", .{});
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

fn upsertGitIgnore(io: Io, cwd: Io.Dir, arena: std.mem.Allocator) !void {
    var gitignore_file = cwd.openFile(io, "./.gitignore", .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => cwd.createFile(io, "./.gitignore", .{ .read = true }) catch |err2| {
            return logError(io, arena, err2, "failure opening .gitignore file");
        },
        else => return logError(io, arena, err, "failure creating .gitignore file"),
    };
    defer gitignore_file.close(io);

    var read_buffer: [1024]u8 = undefined;
    var writer_buffer: [1024]u8 = undefined;

    var reader_obj = gitignore_file.reader(io, &read_buffer);
    var writer_obj = gitignore_file.writerStreaming(io, &writer_buffer);

    var found_gitrotate = false;

    var reader = &reader_obj.interface;
    var writer = &writer_obj.interface;

    while (reader.takeDelimiter('\n')) |line| {
        if (line == null) break;
        if (std.mem.containsAtLeast(u8, line.?, 1, ".gitrotate")) {
            found_gitrotate = true;
            break;
        }
    } else |err| {
        if (err != error.EndOfStream) {
            return logError(io, arena, err, "failure reading .gitignore file");
        }
    }

    if (!found_gitrotate) {
        try writer.writeAll("\n.gitrotate\n");
        try writer.flush();
    }
}
