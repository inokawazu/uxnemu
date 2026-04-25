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

const START_PC = 0x100;

fn mword(bu: u8, bl: u8) u16 {
    return (@as(u16, bu) << 8) | @as(u16, bl);
}

fn rel_offset(pc: u16, offset: u16) u16 {
    const offest_u8: u8 = @truncate(offset);
    const rel: i8 = @bitCast(offest_u8);
    return @intCast(rel + @as(i32, pc));
}

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
    fn popw(self: *Self, k: u1, s: u1) u16 {
        var out: u16 = self.ws[self.wp - 1];
        if (s == 1) {
            out |= @as(u16, self.ws[self.wp - 2]) << 8;
        }
        if (k != 1) self.wp -= 1 + @as(u8, s);
        return out;
    }
    
    // push working stack
    fn pushw(self: *Self, value: u16, s: u1) void {
        if (s==1) {
            self.ws[self.wp] = @truncate((value >> 8) & 0xFF);
            self.wp += 1;
        }
        self.ws[self.wp] = @truncate(value & 0xFF);
        self.wp += 1;
    }

    fn peekw(self: Self) u8 {
        return self.ws[self.wp - 1];
    }

    // pop return stack
    fn popr(self: *Self, k: u1, s: u1) u16 {
        var out: u16 = self.rs[self.rp - 1];
        if (s == 1) {
            out |= @as(u16, self.rs[self.rp - 2]) << 8;
        }
        if (k != 1) self.rp -= 1 + @as(u8, s);
        return out;
    }

    // push return stack
    fn pushr(self: *Self, value: u16, s: u1) void {
        if (s==1) {
            self.rs[self.rp] = @truncate((value >> 8) & 0xFF);
            self.rp += 1;
        }
        self.rs[self.rp] = @truncate(value & 0xFF);
        self.rp += 1;
    }

    fn pop(self: *Self, k: u1, r: u1, s: u1) u16 {
        if (r == 1) {
            return self.popr(k, s);
        } else {
            return self.popw(k, s);
        }
    }

    fn push(self: *Self, value: u16, r: u1, s: u1) void {
        if (r == 1) {
            self.pushr(value, s);
        } else {
            self.pushw(value, s);
        }
    }

    fn jump(self: *Self, addr: u16, s: u1) void {
        if (s == 1) {
            self.pc = addr;
        } else {
            self.pc = rel_offset(self.pc, addr);
            // const addr_u8: u8 = @truncate(addr);
            // const rel: i8 = @bitCast(addr_u8);
            // const new_pc: u16 = @intCast(rel + @as(i32, addr));
            // self.pc = new_pc;
        }
    }

    fn fetch(self: *Self, addr: u16, s: u1) u16 {
        if (s == 1) {
            return mword(self.ram[addr], self.ram[addr + 1]);
        } else {
            return self.ram[addr];
        }
    }

    fn store(self: *Self, x: u16, addr: u16, s: u1) void {
        if (s == 1) {
            self.ram[addr] = @truncate(x >> 8);
            self.ram[addr + 1] = @truncate(x);
        } else {
            self.ram[addr] = @truncate(x);
        }
    }

    fn dei(dev: u16, s: u1) u16 {
        _ = s;
        _ = dev;
        return 0;
    }

    fn deo(dev: u16, x: u16, s: u1) void {
        _ = s;
        _ = dev;
        _ = x;
    }

    fn eval(self: *Self) void {
        while (true) {
            const next_inst = Instruction.from_u8(self.ram[self.pc]);
            self.pc += 1;

            const k = next_inst.keep_mode;
            const r = next_inst.return_mode;
            const s = next_inst.short_mode;

            switch (next_inst.opcode) {
                .BRK => {
                    switch (next_inst.to_u8()) {
                        LIT, LITr => {
                            self.push(self.ram[self.pc], r, s);
                            self.pc += 1;
                        },
                        LIT2, LIT2r => {
                            const x = mword(self.ram[self.pc], self.ram[self.pc + 1]);
                            self.push(x, r, s);
                            self.pc += 2;
                        },
                        BRK => { return; },
                        JCI => {
                            const b= self.pop(k, r, s);
                            if (b != 0) {
                                const x = mword(self.ram[self.pc], self.ram[self.pc + 1]);
                                self.pc = @addWithOverflow(self.pc, x)[0];
                            } else {
                                self.pc += 2;
                            }
                        },
                        JMI => {
                            const x = mword(self.ram[self.pc], self.ram[self.pc + 1]);
                            self.pc = @addWithOverflow(self.pc, x)[0];
                        },
                        JSI => {
                            self.push(self.pc + 2, 1, 1);
                            const x = mword(self.ram[self.pc], self.ram[self.pc + 1]);
                            self.pc = @addWithOverflow(self.pc, x)[0];
                        },
                        else => { unreachable; },
                    }
                },
                .INC => {
                    self.push(self.pop(k, r, s) + 1, r, s);
                },
                .POP => {
                    _ = self.pop(k, r, s);
                },
                .NIP => {
                    const y = self.pop(k, r, s);
                    _ = self.pop(k, r, s);
                    self.push(y, r, s);
                },
                .SWP => {
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(y, r, s);
                    self.push(x, r, s);
                },
                .ROT => { 
                    // x y z -> y z x
                    const z = self.pop(k, r, s);
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(y, r, s); // y
                    self.push(z, r, s); // y z
                    self.push(x, r, s); // y z x
                },
                .DUP => {
                    const x = self.pop(k, r, s);
                    self.push(x, r, s);
                    self.push(x, r, s);
                },
                .OVR => {
                    // TODO: test OVR
                    const y = self.pop(k,r, s);
                    const x = self.pop(k,r, s);
                    self.push(x, r, s);
                    self.push(y, r, s);
                    self.push(x, r, s);
                },
                .EQU => {
                    // TODO: test EQU
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    if (x == y) {
                        self.push(1, r, 0);
                    } else {
                        self.push(0, r, 0);
                    }
                },
                .NEQ => {
                    // TODO: test NEQ
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    if (x != y) {
                        self.push(1, r, 0);
                    } else {
                        self.push(0, r, 0);
                    }
                },
                .GTH => {
                    // TODO: test GTH
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    if (x > y) {
                        self.push(1, r, 0);
                    } else {
                        self.push(0, r, 0);
                    }
                },
                .LTH => {
                    // TODO: test LTH
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    if (x < y) {
                        self.push(1, r, 0);
                    } else {
                        self.push(0, r, 0);
                    }
                },
                .JMP => {
                    //TODO: test JMP
                    const x = self.pop(k, r, s);
                    self.jump(x, s);
                },
                .JCN => {
                    //TODO: test JCN
                    const x = self.pop(k, r, s);
                    const b = self.pop(k, r, 0);
                    if ( b != 0 ) self.jump(x, s);
                },
                .JSR => {
                    //TODO: test JSR
                    const x = self.pop(k, r, s);
                    self.push(self.pc, r ^ 1, 1);
                    self.jump(x, s);
                },
                .STH => {
                    //TODO: test STH
                    const x = self.pop(k, r, s);
                    self.push(x, r ^ 1, s);
                },
                .LDZ => {
                    //TODO: test LDZ
                    const zp = self.pop(k, r, 0);
                    const x = self.fetch(zp, s);
                    self.push(x, r, s);
                },
                .STZ => {
                    //TODO: test STZ
                    const zp = self.pop(k, r, 0);
                    const x = self.pop(k, r, s);
                    self.store(x, zp, s);
                },
                .LDR => {
                    //TODO: test LDR
                    const rel = self.pop(k, r, 0);
                    const addr = rel_offset(self.pc, rel);
                    const x = self.fetch(addr, s);
                    self.push(x, r, s);
                },
                .STR => {
                    //TODO: test STR
                    const rel = self.pop(k, r, 0);
                    const x = self.pop(k, r, s);
                    const addr = rel_offset(self.pc, rel);
                    self.store(x, addr, s);
                },
                .LDA => {
                    //TODO: test LDA
                    const addr = self.pop(k, r, 1);
                    const x = self.fetch(addr, s);
                    self.push(x, r, s);
                },
                .STA => {
                    //TODO: test STA
                    const addr = self.pop(k, r, 1);
                    const x = self.pop(k, r, s);
                    self.store(x, addr, s);
                },
                .DEI => {
                    //TODO: test DEI and implement
                    const dev = self.pop(k, r, 0);
                    const x = CPU.dei(dev, s);
                    self.push(x, r, s);
                },
                .DEO => {
                    //TODO: test DEO and implement
                    const dev = self.pop(k, r, 0);
                    const x = self.pop(k, r, s);
                    CPU.deo(dev, x, s);
                },
                .ADD => {
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(x + y, r, s);
                },
                .SUB => {
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(x - y, r, s);
                },
                .MUL => {
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(x * y, r, s);
                },
                .DIV => {
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(if (y==0) 0 else x/y, r, s);
                },
                .AND => {
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(x & y, r, s);
                },
                .ORA => {
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(x | y, r, s);
                },
                .EOR => {
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(x ^ y, r, s);
                },
                .SFT => {
                    // TODO: test SFT
                    const rl: u8 = @truncate(self.pop(k, r, 0));
                    const rn: u4 = @truncate(rl >> 4);
                    const ln: u4 = @truncate(rl);
                    const x = self.pop(k, r, s);
                    self.push((x >> ln) << rn, r, s);
                },
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


const LIT   = 0x80;
const LIT2  = 0xa0;
const LITr  = 0xc0;
const LIT2r = 0xe0;
const BRK= 0x00;

const JCI = 0x20; 
const JMI = 0x40; 
const JSI = 0x60; 

// 0x00 BRK    0x80 LIT
// 0x20 JCI    0xa0 LIT2
// 0x40 JMI    0xc0 LITr
// 0x60 JSI    0xe0 LIT2r

test "SWP" {
    const swp: Instruction = .{.opcode = .SWP};
    const swp2: Instruction = .{.opcode = .SWP, .short_mode = 1};
    const testints = [_]u8 {
        LIT2,
        0x12,
        0x34,
        LIT2,
        0x56,
        0x78,
        swp.to_u8(),
        swp2.to_u8(),
        0x00,
    };

    var cpu = CPU.init();
    cpu.load_program(&testints);
    cpu.eval();
    try std.testing.expectEqualSlices(u8, &[_]u8{0x78, 0x56, 0x12, 0x34}, cpu.ws[0..4]);
    try std.testing.expectEqual(4, cpu.wp);
}

test "NIP" {
    const nip: Instruction = .{.opcode = .NIP};
    const testints = [_]u8 {
        LIT2,
        0x12,
        0x34,
        nip.to_u8(),
        0x00,
    };

    var cpu = CPU.init();
    cpu.load_program(&testints);
    cpu.eval();

    try std.testing.expectEqual(1, cpu.wp);
    try std.testing.expectEqual(cpu.peekw(), 0x34);
}

test "test LIT2 and POP2" {

    const testints = [_]u8 {
        LIT2,
        0x12,
        0x34,
        LIT2,
        0x56,
        0x78,
        0x00,
    };

    var cpu = CPU.init();
    cpu.load_program(&testints);
    cpu.eval();

    // try std.testing.expectEqual(5, cpu.peekw());
    try std.testing.expectEqual(4, cpu.wp);

    const expected_ws = &[4]u8{0x12, 0x34, 0x56, 0x78};
    try std.testing.expectEqualSlices(u8, expected_ws, cpu.ws[0..4]);

    try std.testing.expectEqual(0x5678, cpu.popw(1, 1));
    try std.testing.expectEqual(0x5678, cpu.popw(0, 1));

    try std.testing.expectEqual(0x34, cpu.popw(1, 0));
    try std.testing.expectEqual(0x1234, cpu.popw(1, 1));
    try std.testing.expectEqual(0x1234, cpu.popw(0, 1));
}


test "ROT" {
    const rot: Instruction = .{ .opcode = .ROT };
    const testints = [_]u8 {
        LIT2,
        0x01,
        0x02, // 1 2
        LIT,
        0x03, // 1 2 3
        rot.to_u8(),
        BRK,
    };
    var cpu = CPU.init();
    cpu.load_program(&testints);
    cpu.eval();

    try std.testing.expectEqual(3, cpu.wp);
    try std.testing.expectEqualSlices(u8, &[_]u8{2, 3, 1,}, cpu.ws[0..cpu.wp]);
}

test "DUP" {
    const dup: Instruction = .{ .opcode = .DUP };
    const dupk: Instruction = .{ .opcode = .DUP, .keep_mode = 1 };
    const dup2: Instruction = .{ .opcode = .DUP, .short_mode = 1 };
    const testints = [_]u8 {
        LIT,
        0x01,
        dup.to_u8(),
        dup2.to_u8(),
        dupk.to_u8(),
        BRK,
    };
    var cpu = CPU.init();
    cpu.load_program(&testints);
    cpu.eval();

    try std.testing.expectEqual(6, cpu.wp);
    const expected_ws = [_]u8{1} ** 6;
    try std.testing.expectEqualSlices(u8, &expected_ws, cpu.ws[0..cpu.wp]);
}

test "test program INC five times, starting from 0x00" {
    const _inc: Instruction = .{.opcode = .INC};
    const inc = _inc.to_u8();
    
    const testints = [_]u8 {
        LIT,
        0x00,
        inc, inc, inc, inc, inc,
        BRK,
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
        LIT,
        0x01,
        LIT,
        0x02,
        add.to_u8(),
        BRK,
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
