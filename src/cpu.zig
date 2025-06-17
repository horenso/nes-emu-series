const std = @import("std");

a: u8,
x: u8,
y: u8,
pc: u16,
sp: u8,
flags: CpuFlags,
_cycles: u32,

// temporary register
opcode: u8,
operand: u8,
address_mode: AddressMode,

const Cpu = @This();

pub const CpuFlags = packed struct(u8) {
    carry: bool,
    zero: bool,
    interrupt_disabled: bool,
    decimal: bool,
    b_flag: bool,
    _always_one: bool,
    overflow: bool,
    negative: bool,
};

pub fn reset(cpu: *Cpu) void {
    cpu.pc = 0xC000;
    cpu.sp = 0xFD;
    cpu.flags.interrupt_disabled = true;
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

fn pushByte(cpu: *Cpu, memory: []u8, byte: u8) void {
    const stack_start: u16 = 0x0100 + @as(u16, @intCast(cpu.sp));
    writeByte(memory, stack_start, byte);
    cpu.sp -%= 1;
}

fn popByte(cpu: *Cpu, memory: []u8) u8 {
    cpu.sp +%= 1;
    const stack_start: u16 = 0x0100 + @as(u16, @intCast(cpu.sp));
    return readByte(memory, stack_start);
}

fn getOperand(cpu: *Cpu, memory: []u8, address_mode: AddressMode) !u8 {
    var operand: u8 = undefined;
    switch (address_mode) {
        .Implied => {},
        .Accumulator => {
            operand = cpu.a;
        },
        .Immediate_Or_Relative => {
            operand = fetchByte(cpu, memory);
        },
        .Absolute => {
            const address = fetchTwoBytes(cpu, memory);
            operand = readByte(memory, address);
        },
        .Absolute_X => {
            const address = fetchTwoBytes(cpu, memory) +% cpu.x +% @intFromBool(cpu.flags.carry);
            operand = readByte(memory, address);
        },
        .Absolute_Y => {
            const address = fetchTwoBytes(cpu, memory) +% cpu.y +% @intFromBool(cpu.flags.carry);
            operand = readByte(memory, address);
        },
        .Zeropage => {
            const lower = fetchByte(cpu, memory);
            const address = combineTwoBytes(lower, 0x00);
            operand = readByte(memory, address);
        },
        .Zeropage_X => {
            const lower = fetchByte(cpu, memory) +% cpu.x;
            const address = combineTwoBytes(lower, 0x00);
            operand = readByte(memory, address);
        },
        .Zeropage_Y => {
            const lower = fetchByte(cpu, memory) +% cpu.y;
            const address = combineTwoBytes(lower, 0x00);
            operand = readByte(memory, address);
        },
        .Indirect => {
            const address_to_pointer = fetchTwoBytes(cpu, memory);
            const address_higher = readByte(memory, address_to_pointer);
            const address_lower = readByte(memory, address_to_pointer + 1);
            const address = combineTwoBytes(address_lower, address_higher);
            operand = readByte(memory, address);
        },
        else => {
            return error.AddressModeNotImpl;
        },
    }
    return operand;
}

fn writeResult(cpu: *Cpu, memory: []u8, address_mode: AddressMode, result: u8) !void {
    switch (address_mode) {
        .Zeropage => {
            const lower = fetchByte(cpu, memory);
            const address = combineTwoBytes(lower, 0x00);
            writeByte(memory, address, result);
        },
        .Zeropage_X => {
            const lower = fetchByte(cpu, memory) +% cpu.x;
            const address = combineTwoBytes(lower, 0x00);
            writeByte(memory, address, result);
        },
        .Zeropage_Y => {
            const lower = fetchByte(cpu, memory) +% cpu.y;
            const address = combineTwoBytes(lower, 0x00);
            writeByte(memory, address, result);
        },
        else => {
            return error.WriteResultWrongAddressMode;
        },
    }
}

const AddressMode = enum(u8) {
    Implied = 0, // The operand is specific to the instruction
    Accumulator, // The operand is the A register
    Immediate_Or_Relative, // The operand is an immediate value
    Absolute, // The operand is a pointer
    Absolute_X, // The operand is a (pointer + X)
    Absolute_Y, // The operand is a (pointer + Y)
    Zeropage, // The operand is a pointer but the high byte is implicitly 0
    Zeropage_X, // The operand is a pointer but the high byte is implicitly 0 low + X
    Zeropage_Y, // The operand is a pointer but the high byte is implicitly 0 low + Y
    Indirect, // The operand is a pointer to a pointer
    X_Indirect, // The operand is a pointer (high = zeropage low = imm + X) to a pointer
    Indirect_Y, // The operand is a pointer to a pointer (+ Y)
};

const address_mode_lookup: [256]AddressMode = addressModeLookup();
const instruction_lookup: [256]Instruction = instructionLookup();

fn instructionLookup() [256]Instruction {
    var lookup = std.mem.zeroInit([256]Instruction, TODO);
    lookup[0x08] = PHP;
    lookup[0x09] = ORA;
    lookup[0x10] = BPL;
    lookup[0x18] = CLC;
    lookup[0x20] = JSR;
    lookup[0x24] = BIT;
    lookup[0x28] = PLP;
    lookup[0x29] = AND;
    lookup[0x30] = BMI;
    lookup[0x34] = BIT;
    lookup[0x3C] = BIT;
    lookup[0x89] = BIT;
    lookup[0x38] = SEC;
    lookup[0x48] = PHA;
    lookup[0x49] = EOR;
    lookup[0x50] = BVC;
    lookup[0x58] = CLI;
    lookup[0x60] = RTS;
    lookup[0x68] = PLA;
    lookup[0x69] = ADC;
    lookup[0x90] = BCC;
    lookup[0x4C] = JMP;
    lookup[0x70] = BVS;
    lookup[0x78] = SEI;
    lookup[0x85] = STA;
    lookup[0x86] = STX;
    lookup[0x88] = DEY;
    lookup[0xE9] = SBC;
    lookup[0xEA] = NOP;
    lookup[0xA0] = LDY;
    lookup[0xA2] = LDX;
    lookup[0xA9] = LDA;
    lookup[0xCa] = DEX;
    lookup[0xC0] = CPY;
    lookup[0xC8] = INY;
    lookup[0xC9] = CMP;
    lookup[0xD0] = BNE;
    lookup[0xB0] = BCS;
    lookup[0xB8] = CLV;
    lookup[0xD8] = CLD;
    lookup[0xE0] = CPX;
    lookup[0xE8] = INX;
    lookup[0xF0] = BEQ;
    lookup[0xF8] = SED;
    return lookup;
}

fn addressModeLookup() [256]AddressMode {
    var lookup = std.mem.zeroes([256]AddressMode);
    lookup[0x08] = .Implied;
    lookup[0x09] = .Immediate_Or_Relative;
    lookup[0x10] = .Implied;
    lookup[0x18] = .Implied;
    lookup[0x20] = .Implied;
    lookup[0x21] = .X_Indirect;
    lookup[0x24] = .Zeropage;
    lookup[0x25] = .Zeropage;
    lookup[0x25] = .Zeropage;
    lookup[0x28] = .Implied;
    lookup[0x29] = .Absolute;
    lookup[0x29] = .Immediate_Or_Relative;
    lookup[0x2D] = .Absolute;
    lookup[0x2D] = .Absolute;
    lookup[0x30] = .Implied;
    lookup[0x31] = .Indirect_Y;
    lookup[0x31] = .Indirect_Y;
    lookup[0x34] = .Zeropage_X;
    lookup[0x35] = .Zeropage_X;
    lookup[0x38] = .Implied;
    lookup[0x39] = .Absolute_Y;
    lookup[0x3C] = .Absolute_X;
    lookup[0x3D] = .Absolute_X;
    lookup[0x48] = .Implied;
    lookup[0x49] = .Immediate_Or_Relative;
    lookup[0x4C] = .Implied;
    lookup[0x50] = .Implied;
    lookup[0x58] = .Implied;
    lookup[0x60] = .Implied;
    lookup[0x68] = .Implied;
    lookup[0x69] = .Immediate_Or_Relative;
    lookup[0x70] = .Immediate_Or_Relative;
    lookup[0x78] = .Implied;
    lookup[0x85] = .Zeropage;
    lookup[0x86] = .Zeropage;
    lookup[0x88] = .Implied;
    lookup[0x89] = .Immediate_Or_Relative;
    lookup[0x90] = .Implied;
    lookup[0xA0] = .Immediate_Or_Relative;
    lookup[0xA2] = .Immediate_Or_Relative;
    lookup[0xA9] = .Immediate_Or_Relative;
    lookup[0xB0] = .Immediate_Or_Relative;
    lookup[0xB8] = .Implied;
    lookup[0xC0] = .Immediate_Or_Relative;
    lookup[0xC8] = .Implied;
    lookup[0xC9] = .Immediate_Or_Relative;
    lookup[0xCa] = .Immediate_Or_Relative;
    lookup[0xD0] = .Implied;
    lookup[0xD8] = .Implied;
    lookup[0xE0] = .Immediate_Or_Relative;
    lookup[0xE1] = .X_Indirect;
    lookup[0xE5] = .Zeropage;
    lookup[0xE8] = .Implied;
    lookup[0xE9] = .Immediate_Or_Relative;
    lookup[0xEA] = .Implied;
    lookup[0xED] = .Absolute;
    lookup[0xF0] = .Implied;
    lookup[0xF1] = .Indirect_Y;
    lookup[0xF5] = .Zeropage_X;
    lookup[0xF8] = .Implied;
    lookup[0xF9] = .Absolute_Y;
    lookup[0xFD] = .Absolute_X;
    return lookup;
}

const Instruction = ?fn (cpu: *Cpu, memory: []u8) void;

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
    cpu.opcode = cpu.fetchByte(memory);
    const instruction = instruction_lookup[cpu.opcode];
    cpu.address_mode = address_mode_lookup[cpu.opcode];

    cpu.operand = getOperand(cpu, memory, cpu.address_mode);
    instruction(cpu, memory);
}

// CPU instructions

fn TODO(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    std.log.err("Unimplemented: {x}", .{cpu.opcode});
    return error.OpcodeNotImpl;
}

fn PHP(cpu: *Cpu, memory: []u8) void {
    // todo: no idea???
    const value = cpu.status_register_u8() | 0b0001_0000;
    pushByte(cpu, memory, value);
}

fn PHA(cpu: *Cpu, memory: []u8) void {
    pushByte(cpu, memory, cpu.a);
}

fn PLP(cpu: *Cpu, memory: []u8) void {
    const value = popByte(cpu, memory);
    cpu.set_status_register_from_u8(value);
    // The B bit is discarded
    cpu.flags.b_flag = false;
}

fn CLC(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.flags.carry = false;
}

fn JSR(cpu: *Cpu, memory: []u8) void {
    const two_bytes = splitBytes(cpu.pc + 1);
    pushByte(cpu, memory, two_bytes.higher);
    pushByte(cpu, memory, two_bytes.lower);

    const subroutine_addr = fetchTwoBytes(cpu, memory);
    cpu.pc = subroutine_addr;
}

fn RTS(cpu: *Cpu, memory: []u8) void {
    const lower = popByte(cpu, memory);
    const higher = popByte(cpu, memory);
    cpu.pc = combineTwoBytes(lower, higher);
    cpu.pc +%= 1;
}

fn BIT(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    const result = cpu.operand & cpu.a;
    cpu.flags.zero = result == 0;
    cpu.flags.overflow = result & 0b0100_0000 != 0;
    cpu.flags.negative = result & 0b1000_0000 != 0;
}

// Arithmetic
fn do_adc(cpu: *Cpu, operand: u8) void {
    const result: u16 = @as(u16, cpu.a) + @as(u16, operand) + @as(u16, @intFromBool(cpu.flags.carry));

    // If the sign of both inputs is different from the sign of the result
    cpu.flags.overflow = (operand ^ result) & (cpu.a ^ result) & 0b1000_0000 != 0;

    cpu.a = @truncate(result);
    cpu.flags.carry = result > 0xFF;
    cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
    cpu.flags.zero = cpu.a == 0;
}

fn ADC(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.add(cpu.operand);
}

fn SBC(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.add(~cpu.operand);
}

fn INX(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.x +%= 1;
    cpu.flags.zero = cpu.x == 0;
    cpu.flags.negative = cpu.x & 0b1000_0000 != 0;
}

fn INY(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.y +%= 1;
    cpu.flags.zero = cpu.y == 0;
    cpu.flags.negative = cpu.y & 0b1000_0000 != 0;
}

fn DEX(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.x -%= 1;
    cpu.flags.zero = cpu.x == 0;
    cpu.flags.negative = cpu.x & 0b1000_0000 != 0;
}

fn DEY(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.y -%= 1;
    cpu.flags.zero = cpu.y == 0;
    cpu.flags.negative = cpu.y & 0b1000_0000 != 0;
}

// Logic operations
fn AND(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.a &= cpu.operand;
    cpu.flags.zero = cpu.a == 0;
    cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
}

fn ORA(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.a |= cpu.operand;
    cpu.flags.zero = cpu.a == 0;
    cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
}

fn EOR(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.a ^= cpu.operand;
    cpu.flags.zero = cpu.a == 0;
    cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
}

fn SEC(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.flags.carry = true;
}

fn CLI(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.flags.interrupt_disabled = false;
}

fn PLA(cpu: *Cpu, memory: []u8) void {
    cpu.a = popByte(cpu, memory);
    cpu.flags.zero = cpu.a == 0;
    cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
}

fn JMP(cpu: *Cpu, memory: []u8) void {
    const result = fetchTwoBytes(cpu, memory);
    cpu.pc = result;
}

fn SEI(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.flags.interrupt_disabled = true;
}

fn STA(cpu: *Cpu, memory: []u8) void {
    try writeResult(cpu, memory, cpu.address_mode, cpu.x);
}

fn STX(cpu: *Cpu, memory: []u8) void {
    try writeResult(cpu, memory, cpu.address_mode, cpu.x);
}

fn STY(cpu: *Cpu, memory: []u8) void {
    try writeResult(cpu, memory, cpu.address_mode, cpu.x);
}

fn NOP(cpu: *Cpu, memory: []u8) void {
    _ = cpu;
    _ = memory;
}

fn LDX(cpu: *Cpu, memory: []u8) void {
    cpu.x = try getOperand(cpu, memory, cpu.address_mode);
    cpu.flags.zero = cpu.x == 0;
    cpu.flags.negative = cpu.x & 0b1000_0000 != 0;
}

fn LDY(cpu: *Cpu, memory: []u8) void {
    cpu.y = try getOperand(cpu, memory, cpu.address_mode);
    cpu.flags.zero = cpu.y == 0;
    cpu.flags.negative = cpu.y & 0b1000_0000 != 0;
}

fn LDA(cpu: *Cpu, memory: []u8) void {
    cpu.a = try getOperand(cpu, memory, cpu.address_mode);
    cpu.flags.zero = cpu.a == 0;
    cpu.flags.negative = cpu.a & 0b1000_0000 != 0;
}

// Compare
fn CMP(cpu: *Cpu, memory: []u8) void {
    const operand = try getOperand(cpu, memory, cpu.address_mode);
    cpu.flags.carry = cpu.a >= operand;
    cpu.flags.zero = cpu.a == operand;
    cpu.flags.negative = (cpu.a -% operand) & 0b1000_0000 != 0;
}

fn CPX(cpu: *Cpu, memory: []u8) void {
    const operand = try getOperand(cpu, memory, cpu.address_mode);
    cpu.flags.carry = cpu.x >= operand;
    cpu.flags.zero = cpu.x == operand;
    cpu.flags.negative = (cpu.x -% operand) & 0b1000_0000 != 0;
}

fn CPY(cpu: *Cpu, memory: []u8) void {
    const operand = try getOperand(cpu, memory, cpu.address_mode);
    cpu.flags.carry = cpu.y >= operand;
    cpu.flags.zero = cpu.y == operand;
    cpu.flags.negative = (cpu.y -% operand) & 0b1000_0000 != 0;
}

// Branches
fn BCS(cpu: *Cpu, memory: []u8) void {
    const jump_addr = fetchByte(cpu, memory);
    if (cpu.flags.carry) {
        cpu.pc +%= jump_addr;
    }
}

fn BCC(cpu: *Cpu, memory: []u8) void {
    const jump_addr = fetchByte(cpu, memory);
    if (!cpu.flags.carry) {
        cpu.pc +%= jump_addr;
    }
}

fn BEQ(cpu: *Cpu, memory: []u8) void {
    const jump_addr = fetchByte(cpu, memory);
    if (cpu.flags.zero) {
        cpu.pc +%= jump_addr;
    }
}

fn BNE(cpu: *Cpu, memory: []u8) void {
    const jump_addr = fetchByte(cpu, memory);
    if (!cpu.flags.zero) {
        cpu.pc +%= jump_addr;
    }
}

fn BVS(cpu: *Cpu, memory: []u8) void {
    const jump_addr = fetchByte(cpu, memory);
    if (cpu.flags.overflow) {
        cpu.pc +%= jump_addr;
    }
}

fn BVC(cpu: *Cpu, memory: []u8) void {
    const jump_addr = fetchByte(cpu, memory);
    if (!cpu.flags.overflow) {
        cpu.pc +%= jump_addr;
    }
}

fn BMI(cpu: *Cpu, memory: []u8) void {
    const jump_addr = fetchByte(cpu, memory);
    if (cpu.flags.negative) {
        cpu.pc +%= jump_addr;
    }
}

fn BPL(cpu: *Cpu, memory: []u8) void {
    const jump_addr = fetchByte(cpu, memory);
    if (!cpu.flags.negative) {
        cpu.pc +%= jump_addr;
    }
}

fn CLV(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.flags.overflow = false;
}

fn CLD(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.flags.decimal = false;
}

fn SED(cpu: *Cpu, memory: []u8) void {
    _ = memory;
    cpu.flags.decimal = true;
}
