const std = @import("std");

const Cpu = @import("cpu.zig");

pub fn main() !void {}

test "nestest.nes" {
    std.testing.log_level = .debug;

    var cpu = std.mem.zeroes(Cpu);
    var memory = std.mem.zeroes([65536]u8);

    // init cpu
    cpu.reset();

    const test_resources_dir = try std.fs.cwd().openDir("test_resources", .{});

    const rom_file = try test_resources_dir.openFile(
        "nestest.nes",
        .{ .mode = .read_only },
    );
    defer rom_file.close();

    try rom_file.seekBy(16);
    _ = try rom_file.read(memory[0xC000..]);

    var log_file = try test_resources_dir.openFile(
        "nestest.log",
        .{ .mode = .read_only },
    );
    defer log_file.close();

    var buf_reader = std.io.bufferedReader(log_file.reader());
    var in_stream = buf_reader.reader();
    var buf: [256]u8 = undefined;

    var line_count: usize = 1;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        {
            const expected_pc = try std.fmt.parseInt(u16, line[0..4], 16);
            std.testing.expectEqual(expected_pc, cpu.pc) catch |e| {
                std.log.err(
                    "line: {} expected PC: {X:02} found: {X:02}\n",
                    .{ line_count, expected_pc, cpu.pc },
                );
                return e;
            };
        }

        {
            const a_pos = std.mem.indexOf(u8, line, "A:") orelse {
                return error.ParseError;
            };
            const expected_a = try std.fmt.parseInt(u8, line[a_pos + 2 .. a_pos + 4], 16);
            std.testing.expectEqual(expected_a, cpu.a) catch |e| {
                std.log.err(
                    "line: {} expected A: {X:02} found: {X:02}\n",
                    .{ line_count, expected_a, cpu.a },
                );
                return e;
            };
        }

        {
            const x_pos = std.mem.indexOf(u8, line, "X:") orelse {
                return error.ParseError;
            };
            const expected_x = try std.fmt.parseInt(u8, line[x_pos + 2 .. x_pos + 4], 16);
            std.testing.expectEqual(expected_x, cpu.x) catch |e| {
                std.log.err(
                    "line: {} expected X: {X:04} found: {X:02}\n",
                    .{ line_count, expected_x, cpu.x },
                );
                return e;
            };
        }

        {
            const y_pos = std.mem.indexOf(u8, line, "Y:") orelse {
                return error.ParseError;
            };
            const expected_y = try std.fmt.parseInt(u8, line[y_pos + 2 .. y_pos + 4], 16);
            std.testing.expectEqual(expected_y, cpu.y) catch |e| {
                std.log.err(
                    "line: {} expected Y: {X:02} found: {X:02}\n",
                    .{ line_count, expected_y, cpu.y },
                );
                return e;
            };
        }

        {
            const sp_pos = std.mem.indexOf(u8, line, "SP:") orelse {
                return error.ParseError;
            };
            const expected_sp = try std.fmt.parseInt(u16, line[sp_pos + 3 .. sp_pos + 5], 16);
            std.testing.expectEqual(expected_sp, cpu.sp) catch |e| {
                std.log.err(
                    "line: {} expected SP: {X:04} found: {X:04}\n",
                    .{ line_count, expected_sp, cpu.sp },
                );
                return e;
            };
        }

        {
            const p_pos = std.mem.indexOf(u8, line, "P:") orelse {
                return error.ParseError;
            };
            const expected_p = try std.fmt.parseInt(u8, line[p_pos + 2 .. p_pos + 4], 16);
            std.testing.expectEqual(expected_p, cpu.status_register_u8()) catch |e| {
                std.log.err(
                    "line: {} expected P: {X:04} found: {X:04}\n",
                    .{ line_count, expected_p, cpu.status_register_u8() },
                );
                return e;
            };
        }

        try cpu.execute(memory[0..]);

        line_count += 1;
    }
}
