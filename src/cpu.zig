const std = @import("std");

a: u8,
x: u8,
y: u8,
pc: u16,
sp: u8,
flags: CpuFlags,

const Cpu = @This();

pub const CpuFlags = struct {
    negative: bool,
    zero: bool,
    carry: bool,
    interrupt_disbale: bool,
    decimal: bool,
    overflow: bool,
};

const OpCode = enum(u8) {
    JMP_abs = 0x4C,
    _,
};

pub fn fetchByte(cpu: *Cpu, memory: []u8) u8 {
    const result = memory[cpu.pc];
    cpu.pc += 1;
    return result;
}

pub fn fetchTwoBytes(cpu: *Cpu, memory: []u8) u16 {
    const first = fetchByte(cpu, memory);
    const second = fetchByte(cpu, memory);
    var result: u16 = second;
    result <<= 8;
    result += first;
    return result;
}

pub fn execute(cpu: *Cpu, memory: []u8) !void {
    const opcode: Cpu.OpCode = @enumFromInt(cpu.fetchByte(memory));
    std.log.info("state: {} new opcode: {}", .{ cpu, opcode });
    switch (opcode) {
        .JMP_abs => {
            const result = fetchTwoBytes(cpu, memory);
            cpu.pc = result;
        },
        else => {
            return error.OpcodeNotImpl;
        },
    }
}
