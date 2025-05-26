const std = @import("std");

const Cpu = @import("cpu.zig");

pub fn main() !void {
    var cpu = std.mem.zeroes(Cpu);
    var memory = std.mem.zeroes([65536]u8);

    // init cpu
    cpu.reset();

    const rom_file = try std.fs.openFileAbsolute("/home/jannis/devel/nes-emu-series/tests/nestest.nes", .{ .mode = .read_only });
    defer rom_file.close();
    try rom_file.seekBy(16);
    _ = try rom_file.read(memory[0xC000..]);

    while (true) {
        try cpu.execute(memory[0..]);
    }
}
