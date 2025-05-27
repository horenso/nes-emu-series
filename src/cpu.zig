const std = @import("std");

a: u8,
x: u8,
y: u8,
pc: u16,
sp: u8,
flags: CpuFlags,
_cycles: u32,

const Cpu = @This();

pub const CpuFlags = packed struct(u8) {
    carry: bool,
    zero: bool,
    interrupt_disbale: bool,
    decimal: bool,
    b_flag: bool,
    _always_one: bool,
    overflow: bool,
    negative: bool,
};

pub fn reset(cpu: *Cpu) void {
    cpu.pc = 0xC000;
    cpu.sp = 0xFD;
    cpu.flags.interrupt_disbale = true;
    cpu.flags._always_one = true;
}

pub fn fetchByte(cpu: *Cpu, memory: []u8) u8 {
    const result = memory[cpu.pc];
    cpu.pc += 1;
    return result;
}

fn combineTwoBytes(lower: u8, higher: u8) u16 {
    var result: u16 = higher;
    result <<= 8;
    result += lower;
    return result;
}

pub fn fetchTwoBytes(cpu: *Cpu, memory: []u8) u16 {
    const first = fetchByte(cpu, memory);
    const second = fetchByte(cpu, memory);
    return combineTwoBytes(first, second);
}

pub fn readByte(memory: []u8, address: u16) u8 {
    return memory[address];
}

pub fn writeByte(memory: []u8, address: u16, byte: u8) void {
    memory[address] = byte;
}

fn push_byte(cpu: *Cpu, memory: []u8, byte: u8) void {
    const stack_start: u16 = 0x0100 + @as(u16, @intCast(cpu.sp));
    writeByte(memory, stack_start, byte);
    cpu.sp -%= 1; // wrap around ??
}

fn pull_byte(cpu: *Cpu, memory: []u8) u8 { // we know in our heart it's pop()
    cpu.sp +%= 1; // wrap around ??
    const stack_start: u16 = 0x0100 + @as(u16, @intCast(cpu.sp));
    return readByte(memory, stack_start);
}

const OpCode = enum(u8) {
    CLC = 0x18, // Clear Carry Flag
    JSR = 0x20, // Jump to Subroutine
    SEC = 0x38, // Set Carry Flag
    CLI = 0x58, // Clear Interrupt Disable Flag
    RTS = 0x60, // Return from Subroutine
    JMP_abs = 0x4C,
    SEI = 0x78, // Set Interrupt Disable Flag
    STX_zero_page = 0x86,
    NOP = 0xEA,
    LDY_imm = 0xA0,
    LDX_imm = 0xA2,
    BCS = 0xB0, // Branch if Carry Set
    CLV = 0xB8, // Clear Overflow Flag
    CLD = 0xD8, // Clear Decimal Flag
    SED = 0xF8, // Set Decimal Flag
    _,
};

pub fn status_register_u8(cpu: *Cpu) u8 {
    return @as(u8, @bitCast(cpu.flags));
}

inline fn print(cpu: *Cpu) void {
    std.log.info("PC: {X:04} A:{X:02} X:{X:02} Y:{X:02} SP:{X:04} P:{X:02}", .{
        cpu.pc,
        cpu.a,
        cpu.x,
        cpu.y,
        cpu.sp,
        cpu.status_register_u8(),
    });
}

pub fn execute(cpu: *Cpu, memory: []u8) !void {
    cpu.print();
    const opcode: Cpu.OpCode = @enumFromInt(cpu.fetchByte(memory));
    switch (opcode) {
        .CLC => {
            cpu.flags.carry = false;
        },
        .JSR => {
            const lower: u8 = @truncate(cpu.pc);
            const higher: u8 = @intCast(cpu.pc >> 8);
            push_byte(cpu, memory, lower);
            push_byte(cpu, memory, higher);

            const subroutine_addr = fetchTwoBytes(cpu, memory);
            cpu.pc = subroutine_addr;
        },
        .SEC => {
            cpu.flags.carry = true;
        },
        .CLI => {
            cpu.flags.interrupt_disbale = false;
        },
        .RTS => {
            const lower = pull_byte(cpu, memory);
            const higher = pull_byte(cpu, memory);
            cpu.pc = combineTwoBytes(lower, higher);
        },
        .JMP_abs => {
            const result = fetchTwoBytes(cpu, memory);
            cpu.pc = result;
        },
        .SEI => {
            cpu.flags.interrupt_disbale = true;
        },
        .STX_zero_page => {
            // todo: not sure about this one
            const offset = fetchByte(cpu, memory);
            writeByte(memory, offset, cpu.x);
        },
        .NOP => {},
        .LDY_imm => {
            cpu.y = fetchByte(cpu, memory);
        },
        .LDX_imm => {
            cpu.x = fetchByte(cpu, memory);
        },
        .BCS => {
            const jump_addr = fetchByte(cpu, memory);
            if (cpu.flags.carry) {
                cpu.pc = jump_addr;
            }
        },
        .CLV => {
            cpu.flags.overflow = false;
        },
        .CLD => {
            cpu.flags.decimal = false;
        },
        .SED => {
            cpu.flags.decimal = true;
        },
        else => {
            std.log.err("Unimpl: {x}", .{opcode});
            return error.OpcodeNotImpl;
        },
    }
}
