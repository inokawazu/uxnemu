const std = @import("std");
const uxn = @import("uxn");

source: []u8,
pos: usize = 0,
gen_ptr: usize = 0,
program: []u8,
max_gen_ptr: usize = 0,
second_pass: bool = false,
labels: std.StringHashMap(u16),
// unresolved_labels: std.AutoHashMap(usize, UnresolvedLabel),
context: []const u8 = DEFAULT_CONTEXT,
// gpa: std.mem.Allocator,
arena: std.mem.Allocator,

const Self = @This();

const WS = "\t\n\x0B\x0C\r ";
const HEX = "0123456789abcdefABCDEF";
const DEFAULT_CONTEXT = "Top";

const AssemblerError = error {
    InvalidAddressingType,
    InvalidImmediateJumpType,
    InvalidLabel,
    InvalidLabelType,
    InvalidName,
    InvalidNumberLiteral,
    InvalidNumberOrLabel,
    MissingLabel,
    NoRightCommentBracket,
    OverflowMemory,
    RelativeAddresOverFlow,
    UnknownInput,
    ZeroPageWrite,
};

pub fn init(arena: std.mem.Allocator, source: []u8) !Self {

    var labels = 
        std.StringHashMap(u16).init(arena);
    try labels.put(DEFAULT_CONTEXT, 0x10);

    const program = try arena.alloc(u8, 0x10000);
    errdefer arena.free(program);
    return .{ 
        .arena = arena,
        .source = source,
        .labels = labels,
        .program = program,
    };
}

pub fn rom(self: *Self) []u8 {
    return self.program[0x100..self.max_gen_ptr+1];
}

fn tryExpectChar(self: *Self, c: u8) bool {
    if (self.pos < self.source.len and self.source[self.pos] == c) {
        self.pos += 1;
        return true;
    } else {
        return false;
    }
}

fn tryExpectCharClass(self: *Self, class: [] const u8) ?u8 {
    for (class) |c| {
        if (self.tryExpectChar(c)) return c;
    }
    return null;
}

fn tryConsumeChar(self: *Self) ?u8 {
    if (self.pos < self.source.len) {
        defer self.pos += 1;
        return self.source[self.pos];
    } else {
        return null;
    }
}

fn tryConsumeNumber(self: *Self) ?u16 {
    const start_pos = self.pos;

    while (self.tryConsumeChar()) |c| {
        if (std.ascii.isWhitespace(c)) {
            self.pos -= 1;
            break;
        }
    }

    const token = self.source[start_pos..self.pos];
    // std.debug.print("token '{s}'\n", .{token});
    return std.fmt.parseInt(u16, token, 16) 
        catch {
            // std.debug.print("token error {s}\n", .{@errorName(err)});
            self.pos = start_pos;
            return null;
        };
}


fn allSlice(comptime T: type, slice: []const T, pred: fn (elem: T) bool) bool {
    for (slice) |elem| {
        if (!pred(elem)) return false;
    }
    return true;
}

fn getLabelAddr(self: *Self, key: []u8) !?u16 {
    const maybe_addr = self.labels.get(key);
    if (self.second_pass) {
        const addr = maybe_addr orelse return AssemblerError.MissingLabel;
        return addr;
    }
    return maybe_addr;
}

fn consumeLabel(self: *Self) ![]u8 {
    const start_pos = self.pos;

    while (self.tryConsumeChar()) |c| {
        if (std.ascii.isWhitespace(c)) {
            self.pos -= 1;
            break;
        }
    }
    const token = self.source[start_pos..self.pos];

    // TODO: check for runic chars
    // TODO: check if isOpCode
    // TODO: add other checks
    if (
        token.len == 0 or allSlice(u8, token, std.ascii.isHex)
    ) {
        // std.debug.print("Invalid Name: '{s}'\n", .{token});
        self.pos = start_pos;
        return AssemblerError.InvalidLabel;
    }

    return token;
}

fn consumeAddressingLabel(self: *Self) ![]u8 {
    var is_relative = false;
    if (self.tryExpectCharClass("/&")) |l| {_ = l; is_relative = true;}

    var label = try self.consumeLabel();
    if (is_relative) {
        const slices = [3][]const u8{self.context, "/", label};
        label = try std.mem.concat(self.arena, u8, &slices);
    }
    return label;
}

fn handleAddressing(self: *Self, atype: u8) !void {
    const Placement = enum {raw, literal};
    const Position = enum {relative, absolute, zero_page};
    var placement: Placement = undefined;
    var position: Position = undefined;
    switch (atype) {
        ',' => { placement = .literal; position = .relative; },  // LIT
        '.' => { placement = .literal; position = .zero_page; }, // LIT
        ';' => { placement = .literal; position = .absolute; },  // LIT2 (absolute)
        '_' => { placement = .raw;     position = .relative; },  // raw relative byte
        '-' => { placement = .raw;     position = .zero_page; }, // raw zero-page byte
        '=' => { placement = .raw;     position = .absolute; },  // raw absolute short
        else => { return AssemblerError.InvalidAddressingType; }
    }

    const label = try self.consumeAddressingLabel();
    const addr = try self.getLabelAddr(label) 
        orelse {
            if (placement == .literal) self.gen_ptr += 1;
            switch (position) {
                .absolute => self.gen_ptr += 2,
                .zero_page, .relative => self.gen_ptr += 1,
            }
            return;
        };

    if (placement == .literal) {
        switch (position) {
            .relative, .zero_page => {
                try self.writeByte(uxn.LIT);
            }, .absolute => {
                try self.writeByte(uxn.LIT2);
            }
        }
    }

    switch (position) {
        .relative => {
            var raddr: i32 = @intCast(addr);
            raddr -= @intCast(self.gen_ptr);
            if ( raddr < -128 or raddr > 127 ) {
                return AssemblerError.RelativeAddresOverFlow;
            } 
            const i8raddr: i8 = @intCast(raddr);
            const u8raddr: u8 = @bitCast(i8raddr);
            try self.writeByte(u8raddr);
        }, .absolute => {
            try self.writeShort(addr);
        }, .zero_page => {
            try self.writeByte(@truncate(addr));
        },
    }
}


pub fn assemble(self: *Self) !void {
    try self._assemble();
    self.pos = 0;
    self.gen_ptr = 0;
    self.max_gen_ptr = 0;
    self.second_pass = true;
    try self._assemble();
    // printStringHashMap(u16, self.labels);
}

fn _assemble(self: *Self) !void {
    errdefer {
        const ub = @min(self.pos+20, self.source.len);
        const snippet = self.arena.dupe(u8, self.source[self.pos..ub]) 
            catch self.source[self.pos..ub];
        std.mem.replaceScalar(u8, snippet, '\n', ' ');
        std.debug.print("Encountered error at position = {d}/{d}: ```{s}...```\n", .{self.pos, self.source.len, snippet});
    }

    while (self.pos < self.source.len) {
        const starting_pos = self.pos;
        if (self.tryExpectChar('(')) {
            var found_lb = false;
            while (self.tryConsumeChar()) |rb| {
                if (rb == ')') { 
                    found_lb = true;
                    break;
                }
            }
            if (!found_lb) {
                return AssemblerError.NoRightCommentBracket;
            }
        } else if (self.tryConsumeInstruction()) |data| {
            try self.writeByte(data);
        } else if (self.tryConsumeNumber()) |num| {
            switch (self.pos - starting_pos) {
                2 => {
                    try self.writeByte(@truncate(num));
                },
                4 => {
                    try self.writeShort(num);
                },
                else => {return AssemblerError.InvalidNumberLiteral;},
            }
        } else if (self.tryExpectCharClass(WS)) |ws| {
            _ = ws;
        } else if (self.tryExpectCharClass("|$")) |lt| {
            var addr: u16 = undefined;

            if (self.tryConsumeNumber()) |num| {
                addr = num;
            } else {
                const label = try self.consumeAddressingLabel(); 
                addr = try self.getLabelAddr(label) orelse 
                    return AssemblerError.InvalidNumberOrLabel;
            }
            switch (lt) {
                '|' => { self.gen_ptr = addr; },
                '$' => { self.gen_ptr += addr; },
                else => { return AssemblerError.InvalidLabelType;}
            }
        // } else if (self.tryExpectChar('$')) {
        //     // TODO: add label
        //     var rel_addr: u16 = undefined;
        //     if (self.tryConsumeNumber()) |num| {
        //         rel_addr = num;
        //     } else {
        //         return AssemblerError.InvalidNumberOrLabel;
        //     }
        //     self.gen_ptr += rel_addr;
        } else if (self.tryExpectCharClass("@&")) |c| {
            var label = try self.consumeLabel();
            if (c == '@') {
                self.context = label;
            } else {
                const slices = [3][]const u8{self.context, "/", label};
                label = try std.mem.concat(self.arena, u8, &slices);
            }
            try self.labels.put(label, @intCast(self.gen_ptr));
        } else if (self.tryExpectCharClass(",.;_-=")) |c| {
            try self.handleAddressing(c);
        } else if (self.tryExpectCharClass("!?")) |jt| {
            const label = try self.consumeAddressingLabel();

            const maybe_addr = try self.getLabelAddr(label);
            if (maybe_addr) |addr| {
                const instByte = switch (jt) {
                    '!' => uxn.JMI,
                    '?' => uxn.JCI,
                    else => {return AssemblerError.InvalidImmediateJumpType;}
                };
                try self.writeByte(instByte);

                var raddr: u32 = addr;
                if (raddr < self.gen_ptr + 2) {
                    raddr += 0x10000;
                }
                raddr -= @intCast(self.gen_ptr);
                raddr -= 2;
                try self.writeShort(@truncate(raddr));
            } else {
                self.gen_ptr += 3;
            }
        } else if (self.tryExpectChar('#')) {
            const literal = self.tryConsumeNumber() 
                orelse return AssemblerError.InvalidNumberLiteral;
            switch (self.pos - starting_pos - 1) {
                2 => {
                    try self.writeByte(uxn.LIT);
                    try self.writeByte(@truncate(literal));
                },
                4 => {
                    try self.writeByte(uxn.LIT2);
                    try self.writeShort(literal);
                },
                else => {return AssemblerError.InvalidNumberLiteral;},
            }
        } else if (self.tryExpectCharClass("[]")) |b| {
            _ = b;
            // do nothing
        } else if (self.tryExpectChar('"')) {
            while (self.tryConsumeChar()) |c| {
                if (std.ascii.isWhitespace(c)) {
                    break;
                } else {
                    try self.writeByte(c);
                }
            }
        } else {
            return AssemblerError.UnknownInput;
        }
    }
}

fn writeShort(self: *Self, short: u16) !void {
    try self.writeByte(@truncate(short >> 8));
    try self.writeByte(@truncate(short >> 0));
}

fn writeByte(self: *Self, byte: u8) !void {
    if (self.gen_ptr < 0x100) {return AssemblerError.ZeroPageWrite;}
    if (self.gen_ptr >= self.program.len) {return AssemblerError.OverflowMemory;}
    self.max_gen_ptr = @max(self.gen_ptr, self.max_gen_ptr);
    self.program[self.gen_ptr] = byte;
    self.gen_ptr += 1;
}

fn tryConsumeInstruction(self: *Self) ?u8 {
    const haystack = self.source[self.pos..];

    // Helper: check prefix and advance pos
    const sw = struct {
        fn f(h: []const u8, needle: []const u8) bool {
            return std.mem.startsWith(u8, h, needle);
        }
    }.f;

    // Special-case: BRK and the immediate-mode opcodes that live in the BRK slot.
    // These must be checked before the generic LIT path.
    if (sw(haystack, "JSI"))  { self.pos += 3; return uxn.JSI;  }
    if (sw(haystack, "JMI"))  { self.pos += 3; return uxn.JMI;  }
    if (sw(haystack, "JCI"))  { self.pos += 3; return uxn.JCI;  }
    if (sw(haystack, "BRK"))  { self.pos += 3; return uxn.BRK;  }

    // Base opcode table (all 32 "normal" opcodes).
    const Entry = struct { name: []const u8, base: uxn.Instruction };
    const opcodes = [_]Entry{
        .{ .name = "LIT", .base = .{.opcode = .BRK, .keep_mode = 1}},
        .{ .name = "INC", .base = .{.opcode = .INC}},
        .{ .name = "POP", .base = .{.opcode = .POP}},
        .{ .name = "NIP", .base = .{.opcode = .NIP}},
        .{ .name = "SWP", .base = .{.opcode = .SWP}},
        .{ .name = "ROT", .base = .{.opcode = .ROT}},
        .{ .name = "DUP", .base = .{.opcode = .DUP}},
        .{ .name = "OVR", .base = .{.opcode = .OVR}},
        .{ .name = "EQU", .base = .{.opcode = .EQU}},
        .{ .name = "NEQ", .base = .{.opcode = .NEQ}},
        .{ .name = "GTH", .base = .{.opcode = .GTH}},
        .{ .name = "LTH", .base = .{.opcode = .LTH}},
        .{ .name = "JMP", .base = .{.opcode = .JMP}},
        .{ .name = "JCN", .base = .{.opcode = .JCN}},
        .{ .name = "JSR", .base = .{.opcode = .JSR}},
        .{ .name = "STH", .base = .{.opcode = .STH}},
        .{ .name = "LDZ", .base = .{.opcode = .LDZ}},
        .{ .name = "STZ", .base = .{.opcode = .STZ}},
        .{ .name = "LDR", .base = .{.opcode = .LDR}},
        .{ .name = "STR", .base = .{.opcode = .STR}},
        .{ .name = "LDA", .base = .{.opcode = .LDA}},
        .{ .name = "STA", .base = .{.opcode = .STA}},
        .{ .name = "DEI", .base = .{.opcode = .DEI}},
        .{ .name = "DEO", .base = .{.opcode = .DEO}},
        .{ .name = "ADD", .base = .{.opcode = .ADD}},
        .{ .name = "SUB", .base = .{.opcode = .SUB}},
        .{ .name = "MUL", .base = .{.opcode = .MUL}},
        .{ .name = "DIV", .base = .{.opcode = .DIV}},
        .{ .name = "AND", .base = .{.opcode = .AND}},
        .{ .name = "ORA", .base = .{.opcode = .ORA}},
        .{ .name = "EOR", .base = .{.opcode = .EOR}},
        .{ .name = "SFT", .base = .{.opcode = .SFT}},
    };

    for (opcodes) |entry| {
        if (sw(haystack, entry.name)) {
            var inst = entry.base;
            var len: usize = entry.name.len;
            const rest = haystack[len..];

            // Mode suffixes may appear in any order: '2', 'r', 'k'
            var i: usize = 0;
            while (i < rest.len) : (i += 1) {
                switch (rest[i]) {
                    '2' => { inst.short_mode = 1;  len += 1; },
                    'r' => { inst.return_mode = 1; len += 1; },
                    'k' => { inst.keep_mode = 1;   len += 1; },
                    else => break,
                }
            }

            self.pos += len;
            return inst.to_u8();
        }
    }

    return null;
}

fn printStringHashMap(comptime T: type, hm: std.StringHashMap(T)) void {
    var kiter = hm.iterator();
        std.debug.print("Entries of hashmap({s}):\n", .{@typeName(T)});
    while (kiter.next()) |key| {
        std.debug.print("\t'{s}': 0x{x:0>4}\n", .{key.key_ptr.*, key.value_ptr.*});
    }
}
