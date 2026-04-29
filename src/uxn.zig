const std = @import("std");

const Opcode = enum(u5) {
    BRK = 0x00,
    INC = 0x01,
    POP = 0x02,
    NIP = 0x03,
    SWP = 0x04,
    ROT = 0x05,
    DUP = 0x06,
    OVR = 0x07,
    EQU = 0x08,
    NEQ = 0x09,
    GTH = 0x0a,
    LTH = 0x0b,
    JMP = 0x0c,
    JCN = 0x0d,
    JSR = 0x0e,
    STH = 0x0f,
    LDZ = 0x10,
    STZ = 0x11,
    LDR = 0x12,
    STR = 0x13,
    LDA = 0x14,
    STA = 0x15,
    DEI = 0x16,
    DEO = 0x17,
    ADD = 0x18,
    SUB = 0x19,
    MUL = 0x1a,
    DIV = 0x1b,
    AND = 0x1c,
    ORA = 0x1d,
    EOR = 0x1e,
    SFT = 0x1f,
};

const LIT:   u8   = 0x80;
const LIT2:  u8   = 0xa0;
const LITr:  u8   = 0xc0;
const LIT2r: u8   = 0xe0;
const BRK:   u8   = 0x00;
const JCI:   u8   = 0x20; 
const JMI:   u8   = 0x40; 
const JSI:   u8   = 0x60; 


// Holds Instruction data
// data lay out 'kr2ooooo'
// k = k mode
// r = r mode
// 2 = '2 mode' (short mode)
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

    pub fn format(self: Instruction, writer: *std.io.Writer) !void {
        switch (self.opcode) {
            .BRK => {
                switch (self.to_u8()) {
                    LIT2, LIT2r, LIT, LITr => { 
                        try writer.print("LIT", .{}); 
                        if (self.short_mode == 1) try writer.print("2", .{}); 
                        if (self.return_mode == 1) try writer.print("r", .{}); 
                        try writer.print("({x:0>2})", .{ self.to_u8() });
                        return;
                    },
                    BRK =>  { return try writer.print("BRK({x:0>2})", .{self.to_u8()});  },
                    JCI =>  { return try writer.print("JCI({x:0>2})", .{self.to_u8()}); },
                    JMI =>  { return try writer.print("JMI({x:0>2})", .{self.to_u8()}); },
                    JSI =>  { return try writer.print("JSI({x:0>2})", .{self.to_u8()}); },
                    else => { return try writer.print("UNK({x:0>2})", .{self.to_u8()}); },
                }
            },
            .INC => { try writer.print("INC", .{}); },
            .POP => { try writer.print("POP", .{}); },
            .NIP => { try writer.print("NIP", .{}); },
            .SWP => { try writer.print("SWP", .{}); },
            .ROT => { try writer.print("ROT", .{}); },
            .DUP => { try writer.print("DUP", .{}); },
            .OVR => { try writer.print("OVR", .{}); },
            .EQU => { try writer.print("EQU", .{}); },
            .NEQ => { try writer.print("NEQ", .{}); },
            .GTH => { try writer.print("GTH", .{}); },
            .LTH => { try writer.print("LTH", .{}); },
            .JMP => { try writer.print("JMP", .{}); },
            .JCN => { try writer.print("JCN", .{}); },
            .JSR => { try writer.print("JSR", .{}); },
            .STH => { try writer.print("STH", .{}); },
            .LDZ => { try writer.print("LDZ", .{}); },
            .STZ => { try writer.print("STZ", .{}); },
            .LDR => { try writer.print("LDR", .{}); },
            .STR => { try writer.print("STR", .{}); },
            .LDA => { try writer.print("LDA", .{}); },
            .STA => { try writer.print("STA", .{}); },
            .DEI => { try writer.print("DEI", .{}); },
            .DEO => { try writer.print("DEO", .{}); },
            .ADD => { try writer.print("ADD", .{}); },
            .SUB => { try writer.print("SUB", .{}); },
            .MUL => { try writer.print("MUL", .{}); },
            .DIV => { try writer.print("DIV", .{}); },
            .AND => { try writer.print("AND", .{}); },
            .ORA => { try writer.print("ORA", .{}); },
            .EOR => { try writer.print("EOR", .{}); },
            .SFT => { try writer.print("SFT", .{}); },
        }
        if (self.short_mode == 1) try writer.print("2", .{}); 
        if (self.keep_mode == 1) try writer.print("k", .{}); 
        if (self.return_mode == 1) try writer.print("r", .{}); 
        try writer.print("({x:0>2})", .{ self.to_u8() });
    }
};

// TODO: make stacks circular
const Stack = [0x100]u8;

// const DeviceMemory= [0xFF + 1]u8;
const RAM = [0x10000]u8;

const START_PC: u16 = 0x100;

fn mword(bu: u8, bl: u8) u16 {
    return (@as(u16, bu) << 8) | @as(u16, bl);
}

fn rel_offset(pc: u16, offset: u8) u16 {
    // test the minus sign, which is the most significant bit.
    const has_minus= offset & (1 << 7) != 0;
    if (has_minus) {
        const rel = ~offset + 1;
        return pc - rel;
    } else {
        return pc + offset;
    }
}

const EvalDEI = struct {
    addr: u16,
    short_mode: u1,
    return_mode: u1,
};

const EvalDEO = struct {
    addr: u16,
    value: u16,
    short_mode: u1,
};

const EvalReturn = union(enum) {
    brk,
    deo: EvalDEO,
    dei: EvalDEI,
};

pub const CPU = struct {
    rp: u8,
    rs: Stack,
    wp: u8,
    ws: Stack,
    pc: u16,
    ram: RAM,

    const Self = @This();

    pub fn init() Self {
        return .{
            .rp = 0,
            .rs =  std.mem.zeroes(Stack),
            .wp = 0,
            .ws = std.mem.zeroes(Stack),
            .pc = START_PC,
            .ram= std.mem.zeroes(RAM),
        };
    }

    pub fn load_rom(self: *Self, program: []const u8) void {
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

    pub fn pop(self: *Self, k: u1, r: u1, s: u1) u16 {
        if (r == 1) {
            return self.popr(k, s);
        } else {
            return self.popw(k, s);
        }
    }

    pub fn push(self: *Self, value: u16, r: u1, s: u1) void {
        if (r == 1) {
            self.pushr(value, s);
        } else {
            self.pushw(value, s);
        }
    }

    pub fn jump(self: *Self, addr: u16, s: u1) void {
        if (s == 1) {
            self.pc = addr;
        } else {
            self.pc = rel_offset(self.pc, @truncate(addr));
        }
    }

    pub fn fetch(self: *Self, addr: u16, s: u1) u16 {
        if (s == 1) {
            return mword(self.ram[addr], self.ram[addr + 1]);
        } else {
            return self.ram[addr];
        }
    }

    pub fn store(self: *Self, x: u16, addr: u16, s: u1) void {
        if (s == 1) {
            self.ram[addr] = @truncate(x >> 8);
            self.ram[addr + 1] = @truncate(x);
        } else {
            self.ram[addr] = @truncate(x);
        }
    }

    pub const eval = cpu_eval;
};

pub const DEIHandler = fn (io: std.Io, self: *CPU, addr: u16, s: u1) u16;
pub const DEOHandler = fn (io: std.Io, self: *CPU, addr: u16, x: u16, s: u1) void;

fn cpu_eval(self: *CPU, io: std.Io, dei: DEIHandler, deo: DEOHandler) void {
        while (true) {
            const next_inst = Instruction.from_u8(self.ram[self.pc]);

            // std.debug.print("{f} (pc = 0x{X:0>4})\n", .{next_inst, self.pc});
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
                        BRK => { 
                            return;
                        },
                        JCI => {
                            // TODO: test JCI
                            const b= self.pop(k, r, 0);
                            if (b != 0) {
                                const x = self.fetch(self.pc, 1);
                                self.pc = @addWithOverflow(self.pc, x)[0];
                            }
                            self.pc = @addWithOverflow(self.pc, 2)[0];
                        },
                        JMI => {
                            const x = self.fetch(self.pc, 1);
                            self.pc = @addWithOverflow(self.pc, x)[0];
                            self.pc = @addWithOverflow(self.pc, 2)[0];
                        },
                        JSI => {
                            const rel = self.fetch(self.pc, 1);
                            self.push(self.pc + 2, 1, 1);
                            self.pc = @addWithOverflow(self.pc, rel)[0];
                            self.pc = @addWithOverflow(self.pc, 2)[0];
                        },
                        else => { unreachable; },
                    }
                },
                .INC => {
                    const y = self.pop(k, r, s);
                    self.push(y + 1, r, s);
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
                    self.push(if (x == y) 1 else 0, r, 0);
                },
                .NEQ => {
                    // TODO: test NEQ
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(if (x != y) 1 else 0, r, 0);
                },
                .GTH => {
                    // TODO: test GTH
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(if (x > y) 1 else 0, r, 0);
                },
                .LTH => {
                    // TODO: test LTH
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(if (x < y) 1 else 0, r, 0);
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
                    const addr = rel_offset(self.pc, @truncate(rel));
                    const x = self.fetch(addr, s);
                    self.push(x, r, s);
                },
                .STR => {
                    //TODO: test STR
                    const rel = self.pop(k, r, 0);
                    const x = self.pop(k, r, s);
                    const addr = rel_offset(self.pc, @truncate(rel));
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
                    const x = dei(io, self, dev, s);
                    self.push(x, r, s);
                },
                .DEO => {
                    //TODO: test DEO and implement
                    const dev = self.pop(k, r, 0);
                    const x = self.pop(k, r, s);
                    deo(io, self, dev, x, s);
                },
                .ADD => {
                    const y = self.pop(k, r, s);
                    const x = self.pop(k, r, s);
                    self.push(y + x, r, s);
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



fn dummy_dei(io: std.Io, _: *CPU, _: u16, _: u1) u16 {
    _ = io;
    return 0;
}

fn dummy_deo(io: std.Io, _: *CPU, _: u16, _: u16, _: u1) void {

    _ = io;
}

fn dummy_io() std.Io {
    var threaded = std.Io.Threaded.init_single_threaded;
    return threaded.io();
}

test "SWP" {
    const io = dummy_io();
    const swp: Instruction = .{.opcode = .SWP};
    const swp2: Instruction = .{.opcode = .SWP, .short_mode = 1};
    const test_program = [_]u8 {
        LIT2,
        0x12,
        0x34,
        LIT2,
        0x56,
        0x78,
        swp.to_u8(),
        swp2.to_u8(),
        BRK,
    };

    var cpu = CPU.init();
    cpu.load_rom(&test_program);
    _ = cpu.eval(io, dummy_dei, dummy_deo);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x78, 0x56, 0x12, 0x34}, cpu.ws[0..4]);
    try std.testing.expectEqual(4, cpu.wp);
}

test "NIP" {
    const io = dummy_io();
    const nip: Instruction = .{.opcode = .NIP};
    const test_program = [_]u8 {
        LIT2,
        0x12,
        0x34,
        nip.to_u8(),
        0x00,
    };

    var cpu = CPU.init();
    cpu.load_rom(&test_program);
    _ = cpu.eval(io, dummy_dei, dummy_deo);

    try std.testing.expectEqual(1, cpu.wp);
    try std.testing.expectEqual(cpu.peekw(), 0x34);
}

test "test LIT2 and POP2" {
    const io = dummy_io();

    const test_program = [_]u8 {
        LIT2,
        0x12,
        0x34,
        LIT2,
        0x56,
        0x78,
        0x00,
    };

    var cpu = CPU.init();
    cpu.load_rom(&test_program);
    _ = cpu.eval(io, dummy_dei, dummy_deo);

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
    const io = dummy_io();
    const rot: Instruction = .{ .opcode = .ROT };
    const test_program = [_]u8 {
        LIT2,
        0x01,
        0x02, // 1 2
        LIT,
        0x03, // 1 2 3
        rot.to_u8(),
        BRK,
    };
    var cpu = CPU.init();
    cpu.load_rom(&test_program);
    _ = cpu.eval(io, dummy_dei, dummy_deo);

    try std.testing.expectEqual(3, cpu.wp);
    try std.testing.expectEqualSlices(u8, &[_]u8{2, 3, 1,}, cpu.ws[0..cpu.wp]);
}

test "DUP" {
    const io = dummy_io();
    const dup: Instruction = .{ .opcode = .DUP };
    const dupk: Instruction = .{ .opcode = .DUP, .keep_mode = 1 };
    const dup2: Instruction = .{ .opcode = .DUP, .short_mode = 1 };
    const test_program = [_]u8 {
        LIT,
        0x01,
        dup.to_u8(),
        dup2.to_u8(),
        dupk.to_u8(),
        BRK,
    };
    var cpu = CPU.init();
    cpu.load_rom(&test_program);
    _ = cpu.eval(io, dummy_dei, dummy_deo);

    try std.testing.expectEqual(6, cpu.wp);
    const expected_ws = [_]u8{1} ** 6;
    try std.testing.expectEqualSlices(u8, &expected_ws, cpu.ws[0..cpu.wp]);
}

test "test program INC five times, starting from 0x00" {
    const io = dummy_io();
    const _inc: Instruction = .{.opcode = .INC};
    const inc = _inc.to_u8();

    const test_program = [_]u8 {
        LIT,
        0x00,
        inc, inc, inc, inc, inc,
        BRK,
    };

    var cpu = CPU.init();
    cpu.load_rom(&test_program);
    _ = cpu.eval(io, dummy_dei, dummy_deo);

    try std.testing.expectEqual(5, cpu.peekw());
    try std.testing.expectEqual(1, cpu.wp);
}

test "test program to find 1 + 2 = 3" {
    const io = dummy_io();
    const add: Instruction = .{.opcode = .ADD};

    // 1 + 2
    const test_program = [_]u8 {
        LIT,
        0x01,
        LIT,
        0x02,
        add.to_u8(),
        BRK,
    };

    var cpu = CPU.init();
    cpu.load_rom(&test_program);
    cpu.eval(io, dummy_dei, dummy_deo);

    // try std.testing.expectEqual(.brk, eval_value);
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

test "check 0x37 = DEO2" {
    const deo2: u8 = 0x37;
    const inst: Instruction = .{
        .keep_mode = 0,
        .return_mode = 0,
        .short_mode = 1,
        .opcode = .DEO 
    };
    try std.testing.expectEqual(inst.opcode, Opcode.DEO);
    try std.testing.expectEqual(inst.short_mode, 1);
    try std.testing.expectEqual(inst.return_mode, 0);
    try std.testing.expectEqual(inst.keep_mode, 0);
    try std.testing.expectEqual(inst.to_u8(), deo2);
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

test "mem fetching" {
    var cpu = CPU.init();
    const values = [_]u8{1,2,3,4,5};
    for (values) |value| {
        cpu.store(value, 0x00 + value, 0);
    }

    for (values) |value| {
        const fetched = cpu.fetch(0x00 + value, 0);
        try std.testing.expectEqual(value, fetched);
    }

    @memset(&cpu.ram, 0);

    for (values) |value| {
        cpu.store(value, 0x00 + 2*value, 1);
    }

    for (values) |value| {
        const fetched = cpu.fetch(0x00 + 2*value + 1, 0);
        try std.testing.expectEqual(value, fetched);
    }
}


test "testing rel_offset for various values positive and negative" {
    const i8_offests = [_]i8{-5, -100, 0, 1, -69, 50};
    const base: u16 = 0x0420;
    const i32_base: i32 = @intCast(base);

    for (i8_offests) |i8_offset| {
        const expected = i32_base + i8_offset;
        const actual = rel_offset(base, @bitCast(i8_offset));
        try std.testing.expectEqual(expected, actual);
    }
}
