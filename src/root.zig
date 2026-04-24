const std = @import("std");

const Opcode = enum(u5) {
    BRK = 0x00,
    EQU = 0x08,
    LDZ = 0x10,
    ADD = 0x18,
    INC = 0x01,
    NEQ = 0x09,
    STZ = 0x11,
    SUB = 0x19,
    POP = 0x02,
    GTH = 0x0a,
    LDR = 0x12,
    MUL = 0x1a,
    NIP = 0x03,
    LTH = 0x0b,
    STR = 0x13,
    DIV = 0x1b,
    SWP = 0x04,
    JMP = 0x0c,
    LDA = 0x14,
    AND = 0x1c,
    ROT = 0x05,
    JCN = 0x0d,
    STA = 0x15,
    ORA = 0x1d,
    DUP = 0x06,
    JSR = 0x0e,
    DEI = 0x16,
    EOR = 0x1e,
    OVR = 0x07,
    STH = 0x0f,
    DEO = 0x17,
    SFT = 0x1f,
};

// Holds Instruction data
// data lay out 'kr2ooooo'
// k = k mode
// r = r mode
// 2 = 2 mode (short mode)
// o = opcode
const Instruction = packed struct {
    opcode: Opcode = Opcode.BRK,
    short_mode: u1 = 0,
    return_mode: u1 = 0,
    keep_mode: u1 = 0,

    fn from_u8(b: u8) Instruction {
        return @bitCast(b);
    }

    fn to_u8(self: Instruction) u8 {
        return @bitCast(self);
    }
};

// TODO: make stacks circular
const Stack = [0xFF + 1]u8;

// const DeviceMemory= [0xFF + 1]u8;
const RAM = [0xFFFF + 1]u8;

// #abcd is equivalent to #ab #cd

const Value = union {
    byte: u8,
    word: u16,
};

const START_PC = 0x100;

const CPU = struct {
    rp: u8,
    rs: Stack,
    wp: u8,
    ws: Stack,
    pc: u16,
    ram: RAM,

    const Self = @This();

    fn init() Self {
        return .{
            .rp = 0,
            .rs =  std.mem.zeroes(Stack),
            .wp = 0,
            .ws = std.mem.zeroes(Stack),
            .pc = START_PC,
            .ram= std.mem.zeroes(RAM),
        };
    }

    fn load_program(self: *Self, program: []const u8) void {
        for (program, START_PC..) |program_memory, ram_i| {
            self.ram[ram_i] = program_memory;
        }
    }
    
    // pop working stack
    fn popw(self: *Self, keep_mode: u1) u8 {
        // get top value
        const out = self.ws[self.wp - 1];
        if (keep_mode != 1) self.wp -= 1;
        return out;
    }
    
    // push working stack
    fn pushw(self: *Self, value: u8) void {
        self.ws[self.wp] = value;
        self.wp += 1;
    }

    fn peekw(self: Self) u8 {
        return self.ws[self.wp - 1];
    }

    // pop return stack
    fn popr(self: *Self, keep_mode: u1) u8 {
        // get top value
        const out = self.rs[self.rp - 1];
        if (keep_mode != 1) self.rp -= 1;
        return out;
    }

    // push return stack
    fn pushr(self: *Self, value: u8) void {
        self.rs[self.rp] = value;
        self.rp += 1;
    }

    fn pop(self: *Self, keep_mode: u1, return_mode: u1) u8 {
        if (return_mode == 1) {
            return self.popr(keep_mode);
        } else {
            return self.popw(keep_mode);
        }
    }

    fn push(self: *Self, value: u8, return_mode: u1) void {
        if (return_mode == 1) {
            self.pushr(value);
        } else {
            self.pushw(value);
        }
    }

    fn jump(self: *Self, addr: u8, s: u1) void {
        // const x = self.pop(k, r);
        if (s == 1) {
            // TODO: implement
            unreachable;
        } else {
            self.pc += @as(u16, addr);
        }
    }

    fn eval(self: *Self) void {
        while (true) {
            const next_inst = Instruction.from_u8(self.ram[self.pc]);
            self.pc += 1;

            const k = next_inst.keep_mode;
            const r = next_inst.return_mode;
            const s = next_inst.short_mode;

            switch (next_inst.opcode) {
                .BRK => {switch (next_inst.to_u8()) {
                    // LIT
                    0x80 => {
                        self.pushw(self.ram[self.pc]);
                        self.pc += 1;
                    },
                    0x00 => { return; }, // BRK
                    else => { unreachable; },
                    }},
                .INC => {
                    if (r == 1) {
                        self.pushr(self.popr(k) + 1);
                    }
                    else {
                        self.pushw(self.popw(k) + 1);
                    }
                },
                .POP => {
                    if (r == 1) {_ = self.popr(k);} else {_ = self.popw(k);}
                },
                .NIP => {
                    const y = self.pop(k, r);
                    _ = self.pop(k, r);
                    self.push(y, r);
                },
                .SWP => {
                    const y = self.pop(k, r);
                    const x = self.pop(k, r);
                    self.push(y, r);
                    self.push(x, r);
                },
                .ROT => { 
                    const z = self.pop(k, r);
                    const y = self.pop(k, r);
                    const x = self.pop(k, r);
                    self.push(y, r);
                    self.push(z, r);
                    self.push(x, r);
                },
                .DUP => {
                    const x = self.pop(k, r);
                    self.push(x, r);
                    self.push(x, r);
                },
                .OVR => {
                    const y = self.pop(k,r);
                    const x = self.pop(k,r);
                    self.push(x,r);
                    self.push(y,r);
                    self.push(x,r);
                },
                .EQU => {
                    const y = self.pop(k, r);
                    const x = self.pop(k, r);
                    if (x == y) {
                        self.push(1, r);
                    } else {
                        self.push(0, r);
                    }
                },
                .NEQ => {
                    const y = self.pop(k, r);
                    const x = self.pop(k, r);
                    if (x != y) {
                        self.push(1, r);
                    } else {
                        self.push(0, r);
                    }
                },
                .GTH => {
                    const y = self.pop(k, r);
                    const x = self.pop(k, r);
                    if (x > y) {
                        self.push(1, r);
                    } else {
                        self.push(0, r);
                    }
                },
                .LTH => {
                    const y = self.pop(k, r);
                    const x = self.pop(k, r);
                    if (x < y) {
                        self.push(1, r);
                    } else {
                        self.push(0, r);
                    }
                },
                .JMP => {
                    const x = self.pop(k, r);
                    self.jump(x, s);
                },
                .JCN => {
                    const x = self.pop(k, r);
                    const b = self.pop(k, r);
                    if ( b == 1 ) self.jump(x, s);
                },
                .JSR => {
                    const x = self.pop(k, r);
                    // 0xpc1_pc2
                    const pc1: u8 = @intCast((self.pc >> 8) & 0xFF);
                    const pc2: u8 = @intCast((self.pc >> 0) & 0xFF);
                    self.push(pc1, r ^ 1);
                    self.push(pc2, r ^ 1);
                    self.jump(x, s);
                },
                .STH => {
                    const x = self.pop(k, r);
                    self.push(x, r ^ 1);
                },
                .LDZ => {
                    const zp = self.pop(k, r);
                    self.push(self.ram[zp], r);
                },
                .STZ => {
                    const zp = self.pop(k, r);
                    const x = self.pop(k, r);
                    self.ram[zp] = x;
                },
                .LDR => {
                    const rel: i8 = @bitCast(self.pop(k, r));
                    const addr: u16 = @intCast((@as(i32, self.pc) + @as(i8, rel)) & 0xFFFF);
                    const x = self.ram[addr];
                    self.push(x, r);
                },
                .STR => {
                    const rel: i8 = @bitCast(self.pop(k, r));
                    const x = self.pop(k, r);
                    const addr: u16 = @intCast((@as(i32, self.pc) + @as(i8, rel)) & 0xFFFF);
                    self.ram[addr] = x;
                },
                .LDA => {
                    // TODO
                    unreachable;
                },
                .STA => {
                    // TODO
                    unreachable;
                },
                .DEI => {
                    // TODO
                    unreachable;
                },
                .DEO => {
                    // TODO
                    unreachable;
                },
                .ADD => {
                    const y = self.pop(k, r);
                    const x = self.pop(k, r);
                    self.push(x + y, r);
                },
                else => { unreachable; },
            }
        }
    }
};

fn lit(r: u1, s: u1) Instruction {
    return .{
        .opcode = .BRK,
        .return_mode = r,
        .short_mode= s,
        .keep_mode = 1,
    };
}

// 0x00 BRK    0x80 LIT
// 0x20 JCI    0xa0 LIT2
// 0x40 JMI    0xc0 LITr
// 0x60 JSI    0xe0 LIT2r


test "test program INC five times, starting from 0x00" {
    const _inc: Instruction = .{.opcode = .INC};
    const inc = _inc.to_u8();
    
    // 1 + 2
    const testints = [_]u8 {
        0x80, // LIT
        0x00, // #00
        inc, inc, inc, inc, inc,
        0x00, // BRK
    };

    var cpu = CPU.init();
    cpu.load_program(&testints);
    cpu.eval();

    try std.testing.expectEqual(5, cpu.peekw());
    try std.testing.expectEqual(1, cpu.wp);
}

test "test program to find 1 + 2 = 3" {
    const add: Instruction = .{.opcode = .ADD};
    
    // 1 + 2
    const testints = [_]u8 {
        0x80, // LIT //
        0x01, // #01
        0x80, // LIT
        0x02, // #02
        add.to_u8(),
        0x00, // BRK
    };

    var cpu = CPU.init();
    cpu.load_program(&testints);
    cpu.eval();

    try std.testing.expectEqual(3, cpu.peekw());
    try std.testing.expectEqual(1, cpu.wp);
}

test "init CPU" {
    const cpu = CPU.init();
    var not_okay = false;

    for (cpu.ram) |memory| {not_okay |= memory != 0;}
    try std.testing.expect(!not_okay);

    for (cpu.rs) |memory| {not_okay |= memory != 0;}
    try std.testing.expect(!not_okay);

    for (cpu.ws) |memory| {not_okay |= memory != 0;}
    try std.testing.expect(!not_okay);
}

test "check 0xb8 = ADD2k" {
    const add2k: u8 = 0xb8;
    const inst = Instruction.from_u8(add2k);
    try std.testing.expectEqual(inst.opcode, Opcode.ADD);
    try std.testing.expectEqual(inst.short_mode, 1);
    try std.testing.expectEqual(inst.return_mode, 0);
    try std.testing.expectEqual(inst.keep_mode, 1);
    try std.testing.expectEqual(inst.to_u8(), add2k);
}

test "check 0xb8 = JMPrk" {
    const jmprk: u8 = 0x40 | 0x80 | 0x0c;
    const inst = Instruction.from_u8(jmprk);
    try std.testing.expectEqual(inst.opcode, Opcode.JMP);
    try std.testing.expectEqual(inst.short_mode, 0);
    try std.testing.expectEqual(inst.return_mode, 1);
    try std.testing.expectEqual(inst.keep_mode, 1);
    try std.testing.expectEqual(inst.to_u8(), jmprk);
}
