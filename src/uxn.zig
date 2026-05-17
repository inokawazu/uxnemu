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

pub const RESET_VECTOR: u16 = 0x100;

const BANKS: usize = 0x10;
const BANK_SIZE: usize = 0x10000;
const RAM_SIZE: usize = BANKS * 0x10000;

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

    pub fn format(self: Instruction, writer: *std.Io.Writer) !void {
        switch (self.opcode) {
            .BRK => {
                switch (self.to_u8()) {
                    LIT2, LIT2r, LIT, LITr => { 
                        try writer.print("LIT", .{}); 
                        if (self.short_mode == 1) try writer.print("2", .{}); 
                        if (self.return_mode == 1) try writer.print("r", .{}); 
                        try writer.print("(0x{x:0>2})", .{ self.to_u8() });
                        return;
                    },
                    BRK =>  { return try writer.print("BRK(0x{X:0>2})", .{self.to_u8()});  },
                    JCI =>  { return try writer.print("JCI(0x{X:0>2})", .{self.to_u8()}); },
                    JMI =>  { return try writer.print("JMI(0x{X:0>2})", .{self.to_u8()}); },
                    JSI =>  { return try writer.print("JSI(0x{X:0>2})", .{self.to_u8()}); },
                    else => { return try writer.print("UNK(0x{X:0>2})", .{self.to_u8()}); },
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
        try writer.print("(0x{X:0>2})", .{ self.to_u8() });
    }
};

// TODO: make stacks circular
const Stack = [0x100]u8;

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

pub fn jump(pc: u16, addr: u16, s: u1) u16 {
    if (s == 1) {
        return addr;
    } else {
        return rel_offset(pc, @truncate(addr));
    }
}



const VMError= error {
    ROMTooLarge,
};

pub const VM = struct {
    stk: [2]Stack,
    ptr: [2]u8,
    ram: []u8,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator) !Self {
        var ram = try gpa.alloc(u8, RAM_SIZE);
        for (0..ram.len) |i| ram[i] = 0;

        return .{
            .ptr = .{0, 0},
            .stk = .{std.mem.zeroes(Stack), std.mem.zeroes(Stack)},
            .ram = ram,
        };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        gpa.free(self.ram);
    }

    pub fn load_rom(self: *Self, program: []const u8) VMError!void {
        if (program.len > BANK_SIZE - RESET_VECTOR) return VMError.ROMTooLarge;
        for (program, RESET_VECTOR..) |program_memory, ram_i| {
            self.ram[ram_i] = program_memory;
        }
    }

    pub fn pop(self: *Self, k: u1, r: u1, s: u1) u16 {
        if (self.ptr[r] <= s) { return 0; }
        var out: u16 = self.stk[r][self.ptr[r] - 1];
        if (s == 1) {
            out |= @as(u16, self.stk[r][self.ptr[r] - 2]) << 8;
        }
        if (k != 1) self.ptr[r] -= 1 + @as(u8, s);
        return out;
    }

    pub fn push(self: *Self, x: u16, r: u1, s: u1) void {
        if (s==1) {
            self.stk[r][self.ptr[r]] = @truncate((x >> 8) & 0xFF);
            self.ptr[r] += 1;
        }
        self.stk[r][self.ptr[r]] = @truncate(x & 0xFF);
        self.ptr[r] += 1;
    }

    fn peekw(self: Self) u8 {
        return self.stk[0][self.ptr[0] - 1];
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

    pub fn eval(vm: *Self, vector_address: u16, deio: Device) void {
        var pc = vector_address;

        while (true) {
            const instruction = Instruction.from_u8(vm.ram[pc]);
            // std.debug.print("running {f}\n", .{instruction});
            const r = instruction.return_mode;
            const s = instruction.short_mode;
            const k = instruction.keep_mode;

            // std.debug.print("pc = 0x{X:0>4}, doing {f}\n", .{pc, instruction});

            pc +%= 1;

            switch (instruction.opcode) {
                .BRK => {
                    switch (instruction.to_u8()) {
                        LIT, LITr, LIT2, LIT2r => {
                            const x = vm.fetch(pc, s);
                            vm.push(x, r, s);
                            pc +%= 1;
                            pc +%= s;
                        },
                        BRK => { 
                            return;
                        },
                        JCI => {
                            // TODO: test JCI
                            const b= vm.pop(k, r, 0);
                            if (b != 0) {
                                const x = vm.fetch(pc, 1);
                                pc +%= x;
                            }
                            pc +%= 2;
                        },
                        JMI => {
                            const x = vm.fetch(pc, 1);
                            pc +%= x;
                            pc +%= 2;
                        },
                        JSI => {
                            const rel = vm.fetch(pc, 1);
                            vm.push(pc + 2, 1, 1);
                            pc +%= rel;
                            pc +%= 2;
                        },
                        else => { unreachable; },
                    }
                },
                .INC => {
                    const y = vm.pop(k, r, s);
                    vm.push(y + 1, r, s);
                },
                .POP => {
                    _ = vm.pop(k, r, s);
                },
                .NIP => {
                    const y = vm.pop(k, r, s);
                    _ = vm.pop(k, r, s);
                    vm.push(y, r, s);
                },
                .SWP => {
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(y, r, s);
                    vm.push(x, r, s);
                },
                .ROT => { 
                    // x y z -> y z x
                    const z = vm.pop(k, r, s);
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(y, r, s); // y
                    vm.push(z, r, s); // y z
                    vm.push(x, r, s); // y z x
                },
                .DUP => {
                    const x = vm.pop(k, r, s);
                    vm.push(x, r, s);
                    vm.push(x, r, s);
                },
                .OVR => {
                    // TODO: test OVR
                    const y = vm.pop(k,r, s);
                    const x = vm.pop(k,r, s);
                    vm.push(x, r, s);
                    vm.push(y, r, s);
                    vm.push(x, r, s);
                },
                .EQU => {
                    // TODO: test EQU
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(if (x == y) 1 else 0, r, 0);
                },
                .NEQ => {
                    // TODO: test NEQ
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(if (x != y) 1 else 0, r, 0);
                },
                .GTH => {
                    // TODO: test GTH
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(if (x > y) 1 else 0, r, 0);
                },
                .LTH => {
                    // TODO: test LTH
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(if (x < y) 1 else 0, r, 0);
                },
                .JMP => {
                    //TODO: test JMP
                    const x = vm.pop(k, r, s);
                    pc = jump(pc, x, s);
                },
                .JCN => {
                    //TODO: test JCN
                    const x = vm.pop(k, r, s);
                    const b = vm.pop(k, r, 0);
                    if ( b != 0 ) pc = jump(pc, x, s);
                },
                .JSR => {
                    //TODO: test JSR
                    const x = vm.pop(k, r, s);
                    vm.push(pc, r ^ 1, 1);
                    pc = jump(pc, x, s);
                },
                .STH => {
                    //TODO: test STH
                    const x = vm.pop(k, r, s);
                    vm.push(x, r ^ 1, s);
                },
                .LDZ => {
                    //TODO: test LDZ
                    const zp = vm.pop(k, r, 0);
                    const x = vm.fetch(zp, s);
                    vm.push(x, r, s);
                },
                .STZ => {
                    //TODO: test STZ
                    const zp = vm.pop(k, r, 0);
                    const x = vm.pop(k, r, s);
                    vm.store(x, zp, s);
                },
                .LDR => {
                    //TODO: test LDR
                    const rel = vm.pop(k, r, 0);
                    const addr = rel_offset(pc, @truncate(rel));
                    const x = vm.fetch(addr, s);
                    vm.push(x, r, s);
                },
                .STR => {
                    //TODO: test STR
                    const rel = vm.pop(k, r, 0);
                    const x = vm.pop(k, r, s);
                    const addr = rel_offset(pc, @truncate(rel));
                    vm.store(x, addr, s);
                },
                .LDA => {
                    //TODO: test LDA
                    const addr = vm.pop(k, r, 1);
                    const x = vm.fetch(addr, s);
                    vm.push(x, r, s);
                },
                .STA => {
                    //TODO: test STA
                    const addr = vm.pop(k, r, 1);
                    const x = vm.pop(k, r, s);
                    vm.store(x, addr, s);
                },
                .DEI => {
                    //TODO: test DEI and implement
                    const dev = vm.pop(k, r, 0);
                    const x = deio.dei(vm, @truncate(dev), s);
                    vm.push(x, r, s);
                },
                .DEO => {
                    //TODO: test DEO and implement
                    const dev = vm.pop(k, r, 0);
                    const x = vm.pop(k, r, s);
                    deio.deo(vm, @truncate(dev), x, s);
                },
                .ADD => {
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(y + x, r, s);
                },
                .SUB => {
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(x - y, r, s);
                },
                .MUL => {
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(x * y, r, s);
                },
                .DIV => {
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(if (y==0) 0 else x/y, r, s);
                },
                .AND => {
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(x & y, r, s);
                },
                .ORA => {
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(x | y, r, s);
                },
                .EOR => {
                    const y = vm.pop(k, r, s);
                    const x = vm.pop(k, r, s);
                    vm.push(x ^ y, r, s);
                },
                .SFT => {
                    // TODO: test SFT
                    const lr: u8 = @truncate(vm.pop(k, r, 0));
                    const ln: u4 = @truncate(lr >> 4);
                    const rn: u4 = @truncate(lr);
                    const x = vm.pop(k, r, s);
                    vm.push((x >> rn) << ln, r, s);
                },
            }
        }


    }
};

pub const Device= struct {
    const Self = @This();

    ptr:    *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        dei: *const fn (ctx: *anyopaque, vm: *VM, addr: u8, s: u1) u16,
        deo: *const fn (ctx: *anyopaque, vm: *VM, addr: u8, x: u16, s: u1) void,
    };

    pub fn init(ptr: anytype) Self {
        const gen = struct {
            const T = @TypeOf(ptr);
            fn deiFn(ctx: *anyopaque, vm: *VM, addr: u8, s: u1) u16 {
                const self: T = @ptrCast(@alignCast(ctx));
                return self.dei(vm, addr, s);
            }
            fn deoFn(ctx: *anyopaque, vm: *VM, addr: u8, x: u16, s: u1) void {
                const self: T = @ptrCast(@alignCast(ctx));
                return self.deo(vm, addr, x, s);
            }
            const vtable = VTable{ 
                .dei = deiFn,
                .deo = deoFn 
            };
        };
        return .{ .ptr = ptr, .vtable = &gen.vtable };
    }

    /// Read port — returns value on the bus.
    pub inline fn dei(self: Self, vm: *VM, addr: u8, s: u1) u16 {
        return self.vtable.dei(self.ptr, vm, addr, s);
    }

    /// Write port.
    pub inline fn deo(self: Self, vm: *VM, addr: u8, x: u16, s: u1) void {
        self.vtable.deo(self.ptr, vm, addr, x, s);
    }
};

const DummyDevice = struct {
    pub fn dei(_: *@This(), _: *VM, _: u8, _: u1) u16 { return 0; }
    pub fn deo(_: *@This(), _: *VM, _: u8, _: u16, _: u1) void {}
};


test "SWP" {
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

    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit(std.testing.allocator);
    try vm.load_rom(&test_program);
    var dd: DummyDevice = .{};
    vm.eval(RESET_VECTOR, Device.init(&dd));
    try std.testing.expectEqualSlices(u8, &[_]u8{0x78, 0x56, 0x12, 0x34}, vm.stk[0][0..4]);
    try std.testing.expectEqual(4, vm.ptr[0]);
}

test "NIP" {
    const nip: Instruction = .{.opcode = .NIP};
    const test_program = [_]u8 {
        LIT2,
        0x12,
        0x34,
        nip.to_u8(),
        0x00,
    };

    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit(std.testing.allocator);
    try vm.load_rom(&test_program);
    var dev: DummyDevice = .{};
    vm.eval(RESET_VECTOR, Device.init(&dev));

    try std.testing.expectEqual(1, vm.ptr[0]);
    try std.testing.expectEqual(vm.peekw(), 0x34);
}

test "test LIT2 and POP2" {

    const test_program = [_]u8 {
        LIT2,
        0x12,
        0x34,
        LIT2,
        0x56,
        0x78,
        0x00,
    };

    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit(std.testing.allocator);
    try vm.load_rom(&test_program);
    var dd: DummyDevice = .{};
    vm.eval(RESET_VECTOR, Device.init(&dd));

    // try std.testing.expectEqual(5, vm.peekw());
    try std.testing.expectEqual(4, vm.ptr[0]);

    const expected_ws = &[4]u8{0x12, 0x34, 0x56, 0x78};
    try std.testing.expectEqualSlices(u8, expected_ws, vm.stk[0][0..4]);

    try std.testing.expectEqual(0x5678, vm.pop(1, 0, 1));
    try std.testing.expectEqual(0x5678, vm.pop(0, 0, 1));

    try std.testing.expectEqual(0x34, vm.pop(1, 0, 0));
    try std.testing.expectEqual(0x1234, vm.pop(1, 0, 1));
    try std.testing.expectEqual(0x1234, vm.pop(0, 0, 1));
}


test "ROT" {
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
    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit(std.testing.allocator);
    try vm.load_rom(&test_program);
    var dd: DummyDevice = .{};
    vm.eval(RESET_VECTOR, Device.init(&dd));

    try std.testing.expectEqual(3, vm.ptr[0]);
    try std.testing.expectEqualSlices(u8, 
        &[_]u8{2, 3, 1,}, vm.stk[0][0..vm.ptr[0]]
    );
}

test "DUP" {
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
    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit(std.testing.allocator);
    try vm.load_rom(&test_program);
    var dd: DummyDevice = .{};
    vm.eval(RESET_VECTOR, Device.init(&dd));

    try std.testing.expectEqual(6, vm.ptr[0]);
    const expected_ws = [_]u8{1} ** 6;
    try std.testing.expectEqualSlices(u8, &expected_ws, vm.stk[0][0..vm.ptr[0]]);
}

test "test program INC five times, starting from 0x00" {
    const _inc: Instruction = .{.opcode = .INC};
    const inc = _inc.to_u8();

    const test_program = [_]u8 {
        LIT,
        0x00,
        inc, inc, inc, inc, inc,
        BRK,
    };

    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit(std.testing.allocator);
    try vm.load_rom(&test_program);
    var dd: DummyDevice = .{};
    vm.eval(RESET_VECTOR, Device.init(&dd));

    try std.testing.expectEqual(5, vm.peekw());
    try std.testing.expectEqual(1, vm.ptr[0]);
}

test "test program to find 1 + 2 = 3" {
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

    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit(std.testing.allocator);
    try vm.load_rom(&test_program);
    var dd: DummyDevice = .{};
    vm.eval(RESET_VECTOR, Device.init(&dd));

    try std.testing.expectEqual(3, vm.peekw());
    try std.testing.expectEqual(1, vm.ptr[0]);
}

test "init CPU" {
    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit(std.testing.allocator);
    var not_okay = false;

    for (vm.ram) |memory| {not_okay |= memory != 0;}
    try std.testing.expect(!not_okay);

    for (vm.stk[1]) |memory| {not_okay |= memory != 0;}
    try std.testing.expect(!not_okay);

    for (vm.stk[0]) |memory| {not_okay |= memory != 0;}
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
    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit(std.testing.allocator);
    const values = [_]u8{1,2,3,4,5};
    for (values) |value| {
        vm.store(value, 0x00 + value, 0);
    }

    for (values) |value| {
        const fetched = vm.fetch(0x00 + value, 0);
        try std.testing.expectEqual(value, fetched);
    }

    @memset(vm.ram, 0);

    for (values) |value| {
        vm.store(value, 0x00 + 2*value, 1);
    }

    for (values) |value| {
        const fetched = vm.fetch(0x00 + 2*value + 1, 0);
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
