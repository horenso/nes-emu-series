const std = @import("std");

const Cpu = @import("cpu.zig");

pub fn main() !void {
    var cpu = std.mem.zeroes(Cpu);
    var memory = std.mem.zeroes([65536]u8);
    memory[0] = 0x4C;
    memory[1] = 0xF5;
    memory[2] = 0xC5;

    while (true) {
        try cpu.execute(memory[0..]);
    }
}
