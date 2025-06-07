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
    result |= lower;
    return result;
}

const TwoBytes = struct { lower: u8, higher: u8 };

fn splitBytes(value: u16) TwoBytes {
    const lower: u8 = @truncate(value);
    const higher: u8 = @intCast(value >> 8);
    return .{ .lower = lower, .higher = higher };
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
    cpu.sp -%= 1;
}

fn pop_byte(cpu: *Cpu, memory: []u8) u8 {
    cpu.sp +%= 1;
    const stack_start: u16 = 0x0100 + @as(u16, @intCast(cpu.sp));
    return readByte(memory, stack_start);
}

const OpCode = enum(u8) {
    PHP = 0x08, // Push Processor Status
    ORA = 0x09, // ORA - Logical Inclusive OR
    BPL = 0x10, // Branch if Positive
    CLC = 0x18, // Clear Carry Flag
    JSR = 0x20, // Jump to Subroutine
    BIT = 0x24, // Bit Test
    PLP = 0x28, // Pull Processor Status
    AND = 0x29, // Logical AND
    BMI = 0x30, // Branch if Minus
    SEC = 0x38, // Set Carry Flag
    PHA = 0x48, // Push Accumulator
    EOR = 0x49, // Exclusive OR
    BVC = 0x50, // Branch if Overflow Clear
    CLI = 0x58, // Clear Interrupt Disable Flag
    RTS = 0x60, // Return from Subroutine
    PLA = 0x68, // Pull Accumulator
    ADC = 0x69, // Add with Carry
    BCC = 0x90, // Branch if Carry Clear
    JMP_abs = 0x4C,
    BVS = 0x70, // Branch if Overflow Set
    SEI = 0x78, // Set Interrupt Disable Flag
    STA = 0x85, // Store Accumulator
    STX_zero_page = 0x86,
    SBC = 0xE9, // Subtract with Carry
    NOP = 0xEA, // No Operation
    LDY_imm = 0xA0,
    LDX_imm = 0xA2,
    LDA_imm = 0xA9, // Load Accumulator
    CPY_imm = 0xC0, // Compare Y Register
    INY = 0xC8, // Increment Y Register
    CMP = 0xC9, // Compare
    BNE = 0xD0, // Branch if Not Equal
    BCS = 0xB0, // Branch if Carry Set
    CLV = 0xB8, // Clear Overflow Flag
    CLD = 0xD8, // Clear Decimal Flag
    CPX_imm = 0xE0, // Compare X Register
    INX = 0xE8, // Increment X Register
    BEQ = 0xF0, // BEQ - Branch if Equal
    SED = 0xF8, // Set Decimal Flag
    _,
};

pub fn status_register_u8(cpu: *Cpu) u8 {
    return @as(u8, @bitCast(cpu.flags));
}

pub fn set_status_register_from_u8(cpu: *Cpu, value: u8) void {
    cpu.flags = @bitCast(value);
    cpu.flags._always_one = true;
}

pub fn print(cpu: *Cpu) void {
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
    const opcode: Cpu.OpCode = @enumFromInt(cpu.fetchByte(memory));
    switch (opcode) {
        .PHP => {
            // todo: no idea???
            const value = cpu.status_register_u8() | 0b0001_0000;
            push_byte(cpu, memory, value);
        },
        .PHA => {
            push_byte(cpu, memory, cpu.a);
        },
        .PLP => {
            const value = pop_byte(cpu, memory);
            cpu.set_status_register_from_u8(value);
            // The B bit is discarded
            cpu.flags.b_flag = false;
        },
        .CLC => {
            cpu.flags.carry = false;
        },
        .JSR => {
            const two_bytes = splitBytes(cpu.pc + 1);
            push_byte(cpu, memory, two_bytes.higher);
            push_byte(cpu, memory, two_bytes.lower);

            const subroutine_addr = fetchTwoBytes(cpu, memory);
            cpu.pc = subroutine_addr;
        },
        .RTS => {
            const lower = pop_byte(cpu, memory);
            const higher = pop_byte(cpu, memory);
            cpu.pc = combineTwoBytes(lower, higher);
            cpu.pc +%= 1;
        },
        .BIT => {
            const address: u16 = @intCast(fetchByte(cpu, memory));
            const value = readByte(memory, address);
            const anded_value = value & cpu.a;
            cpu.flags.zero = anded_value == 0;
            cpu.flags.overflow = value & 0b0100_0000 != 0;
            cpu.flags.negative = value & 0b1000_0000 != 0;
        },
        // Arithmatic
        .ADC => {
            const operand: u16 = fetchByte(cpu, memory);
            const result: u16 = @as(u16, cpu.a) + operand + @as(u16, @intFromBool(cpu.flags.carry));

            const cpu_a_before = cpu.a;

            cpu.a = @truncate(result);
            cpu.flags.carry = result > 0xFF;
            cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
            cpu.flags.zero = cpu.a == 0;
            // If the sign of both inputs is different from the sign of the result
            cpu.flags.overflow = (operand ^ result) & (cpu_a_before ^ result) & 0b1000_0000 != 0;
        },
        .SBC => {
            const operand: u16 = fetchByte(cpu, memory);
            const result: u16 = @as(u16, cpu.a) -% operand - (1 -% @as(u16, @intFromBool(cpu.flags.carry)));

            const cpu_a_before = cpu.a;

            cpu.a = @truncate(result);
            cpu.flags.carry = result <= 0xFF;
            cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
            cpu.flags.zero = cpu.a == 0;
            // If the sign of both inputs is different from the sign of the result
            cpu.flags.overflow = (operand ^ result) & (cpu_a_before ^ result) & 0b1000_0000 != 0;
        },
        .INX => {
            cpu.x +%= 1;
            cpu.flags.zero = cpu.x == 0;
            cpu.flags.negative = cpu.x & 0b1000_0000 != 0;
        },
        .INY => {
            cpu.y +%= 1;
            cpu.flags.zero = cpu.y == 0;
            cpu.flags.negative = cpu.y & 0b1000_0000 != 0;
        },

        // Logic operations
        .AND => {
            const value = fetchByte(cpu, memory);
            cpu.a &= value;
            cpu.flags.zero = cpu.a == 0;
            cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
        },
        .ORA => {
            const value = fetchByte(cpu, memory);
            cpu.a |= value;
            cpu.flags.zero = cpu.a == 0;
            cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
        },
        .EOR => {
            const value = fetchByte(cpu, memory);
            cpu.a ^= value;
            cpu.flags.zero = cpu.a == 0;
            cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
        },

        .SEC => {
            cpu.flags.carry = true;
        },
        .CLI => {
            cpu.flags.interrupt_disbale = false;
        },
        .PLA => {
            cpu.a = pop_byte(cpu, memory);
            cpu.flags.zero = cpu.a == 0;
            cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
        },
        .JMP_abs => {
            const result = fetchTwoBytes(cpu, memory);
            cpu.pc = result;
        },
        .SEI => {
            cpu.flags.interrupt_disbale = true;
        },
        .STA => {
            const address: u16 = @intCast(fetchByte(cpu, memory));
            writeByte(memory, address, cpu.a);
        },
        .STX_zero_page => {
            // todo: not sure about this one
            const offset = fetchByte(cpu, memory);
            writeByte(memory, offset, cpu.x);
        },
        .NOP => {},
        .LDY_imm => {
            cpu.y = fetchByte(cpu, memory);
            cpu.flags.zero = cpu.y == 0;
            cpu.flags.negative = cpu.y & 0b1000_0000 != 0;
        },
        .LDX_imm => {
            cpu.x = fetchByte(cpu, memory);
            cpu.flags.zero = cpu.x == 0;
            cpu.flags.negative = cpu.x & 0b1000_0000 != 0;
        },
        .LDA_imm => {
            cpu.a = fetchByte(cpu, memory);
            cpu.flags.zero = cpu.a == 0;
            cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
        },

        // Compare
        .CMP => {
            const immediate_value = fetchByte(cpu, memory);
            cpu.flags.carry = cpu.a >= immediate_value;
            cpu.flags.zero = cpu.a == immediate_value;
            cpu.flags.negative = (cpu.a -% immediate_value) & 0b1000_0000 != 0;
        },
        .CPX_imm => {
            const immediate_value = fetchByte(cpu, memory);
            cpu.flags.carry = cpu.x >= immediate_value;
            cpu.flags.zero = cpu.x == immediate_value;
            cpu.flags.negative = (cpu.x -% immediate_value) & 0b1000_0000 != 0;
        },
        .CPY_imm => {
            const immediate_value = fetchByte(cpu, memory);
            cpu.flags.carry = cpu.y >= immediate_value;
            cpu.flags.zero = cpu.y == immediate_value;
            cpu.flags.negative = (cpu.y -% immediate_value) & 0b1000_0000 != 0;
        },

        // Branches
        .BCS => {
            const jump_addr = fetchByte(cpu, memory);
            if (cpu.flags.carry) {
                cpu.pc +%= jump_addr;
            }
        },
        .BCC => {
            const jump_addr = fetchByte(cpu, memory);
            if (!cpu.flags.carry) {
                cpu.pc +%= jump_addr;
            }
        },
        .BEQ => {
            const jump_addr = fetchByte(cpu, memory);
            if (cpu.flags.zero) {
                cpu.pc +%= jump_addr;
            }
        },
        .BNE => {
            const jump_addr = fetchByte(cpu, memory);
            if (!cpu.flags.zero) {
                cpu.pc +%= jump_addr;
            }
        },
        .BVS => {
            const jump_addr = fetchByte(cpu, memory);
            if (cpu.flags.overflow) {
                cpu.pc +%= jump_addr;
            }
        },
        .BVC => {
            const jump_addr = fetchByte(cpu, memory);
            if (!cpu.flags.overflow) {
                cpu.pc +%= jump_addr;
            }
        },
        .BMI => {
            const jump_addr = fetchByte(cpu, memory);
            if (cpu.flags.negative) {
                cpu.pc +%= jump_addr;
            }
        },
        .BPL => {
            const jump_addr = fetchByte(cpu, memory);
            if (!cpu.flags.negative) {
                cpu.pc +%= jump_addr;
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
