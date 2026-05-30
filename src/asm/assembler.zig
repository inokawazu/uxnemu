const std = @import("std");
const uxn = @import("uxn");
const Lexer = @import("lexer.zig");

source: []u8,
pos: usize = 0,
gen_ptr: usize = 0,
max_gen_ptr: usize = 0,
anon_id: u16 = 0,
program: []u8,
// second_pass: bool = false,
labels: std.StringHashMap(u16),
unresolved_labels: std.ArrayList(UnresolvedLabel),
anon_id_stack: std.ArrayList(u16),
context: []const u8 = DEFAULT_CONTEXT,
arena: std.mem.Allocator,

const Self = @This();

const WS = "\t\n\x0B\x0C\r ";
const HEX = "0123456789abcdefABCDEF";
const DEFAULT_CONTEXT = "Top";

const AssemblerError = error{
    UnmatchedLeftAnonBracket,
    UnresolvedMacro,
    NoMacroBrackets,
    UnmatchedLeftMacroBracket,
    UnmatchedRightMacroBracket,
    DuplicateLabel,
    InvalidDefLabel,
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
    UnmatchedRightAnonBracket,
    ZeroLengthLabel,
    ZeroPageWrite,
};

const UnresolvedLabel = struct {
    ultype: UnresolvedLabelType,
    label: []const u8,
    gen_ptr: u16,
};

const UnresolvedLabelType = enum {
    immediate,
    relative,
    absolute,
    zero_page,
};

pub fn init(arena: std.mem.Allocator, source: []u8) !Self {
    var labels =
        std.StringHashMap(u16).init(arena);
    try labels.put(DEFAULT_CONTEXT, 0x10);

    const unresolved_labels = 
        try std.ArrayList(UnresolvedLabel).initCapacity(arena, 0);

    const anon_id_stack = 
        try std.ArrayList(u16).initCapacity(arena, 32);

    const program = try arena.alloc(u8, 0x10000);
    errdefer arena.free(program);
    return .{
        .arena = arena,
        .source = source,
        .labels = labels,
        .program = program,
        .unresolved_labels = unresolved_labels,
        .anon_id_stack = anon_id_stack,
    };
}


const NON_LABEL_START_RUNES = "|$@,_.-;=!?#\"{}~()[]%";

fn tryIntParse(comptime T: type, buf: []const u8, base: u8) ?T {
    return std.fmt.parseInt(T, buf, base) catch {return null;};
}

const AddrOrLabel = union(enum) {
    addr: u16,
    label: []const u8,
};

fn parseLabelOrAddress(self: *Self, toparse: []const u8) !AddrOrLabel {
    if (tryIntParse(u16, toparse, 16)) |addr| {
        return .{ .addr = addr };
    }

    const label = try self.parseLabel(toparse);
    return .{ .label = label };
}

fn parseLabel(self: *Self, toparse: []const u8) ![]const u8 {
    var label = toparse;

    if (label.len == 0) {
        return AssemblerError.ZeroLengthLabel;
    }

    if (label.len == 1 and label[0] == '{') {
        const id = self.anon_id;
        try self.anon_id_stack.append(self.arena, id);
        self.anon_id += 1;
        return try std.fmt.allocPrint(self.arena, "{{}}lambda{x:0>4}", .{id});
    }

    const is_bad_start = std.mem.find(u8, NON_LABEL_START_RUNES, label[0..1]) != null;
    if (is_bad_start) {
        return AssemblerError.InvalidLabel;
    }

    const is_relative = toparse[0] == '&' or toparse[0] == '/';

    if (is_relative) {
        const slices = [3][]const u8{ self.context, "/", label[1..] };
        label = try std.mem.concat(self.arena, u8, &slices);
    }

    return label;
}

fn tryParseInstruction(to_parse: []const u8) ?u8 {
    // Helper: check prefix and advance pos
    const sw = struct {
        fn f(h: []const u8, needle: []const u8) bool {
            return std.mem.startsWith(u8, h, needle);
        }
    }.f;

    if (sw(to_parse, "JSI"))
        return uxn.JSI;
    if (sw(to_parse, "JMI"))
        return uxn.JMI;
    if (sw(to_parse, "JCI"))
        return uxn.JCI;
    if (sw(to_parse, "BRK")) 
        return uxn.BRK;

    // Base opcode table (all 32 "normal" opcodes).
    const Entry = struct { name: []const u8, base: uxn.Instruction };
    const opcodes = [_]Entry{
        .{ .name = "LIT", 
            .base = .{ .opcode = .BRK, .keep_mode = 1 } },
        .{ .name = "INC", .base = .{ .opcode = .INC } },
        .{ .name = "POP", .base = .{ .opcode = .POP } },
        .{ .name = "NIP", .base = .{ .opcode = .NIP } },
        .{ .name = "SWP", .base = .{ .opcode = .SWP } },
        .{ .name = "ROT", .base = .{ .opcode = .ROT } },
        .{ .name = "DUP", .base = .{ .opcode = .DUP } },
        .{ .name = "OVR", .base = .{ .opcode = .OVR } },
        .{ .name = "EQU", .base = .{ .opcode = .EQU } },
        .{ .name = "NEQ", .base = .{ .opcode = .NEQ } },
        .{ .name = "GTH", .base = .{ .opcode = .GTH } },
        .{ .name = "LTH", .base = .{ .opcode = .LTH } },
        .{ .name = "JMP", .base = .{ .opcode = .JMP } },
        .{ .name = "JCN", .base = .{ .opcode = .JCN } },
        .{ .name = "JSR", .base = .{ .opcode = .JSR } },
        .{ .name = "STH", .base = .{ .opcode = .STH } },
        .{ .name = "LDZ", .base = .{ .opcode = .LDZ } },
        .{ .name = "STZ", .base = .{ .opcode = .STZ } },
        .{ .name = "LDR", .base = .{ .opcode = .LDR } },
        .{ .name = "STR", .base = .{ .opcode = .STR } },
        .{ .name = "LDA", .base = .{ .opcode = .LDA } },
        .{ .name = "STA", .base = .{ .opcode = .STA } },
        .{ .name = "DEI", .base = .{ .opcode = .DEI } },
        .{ .name = "DEO", .base = .{ .opcode = .DEO } },
        .{ .name = "ADD", .base = .{ .opcode = .ADD } },
        .{ .name = "SUB", .base = .{ .opcode = .SUB } },
        .{ .name = "MUL", .base = .{ .opcode = .MUL } },
        .{ .name = "DIV", .base = .{ .opcode = .DIV } },
        .{ .name = "AND", .base = .{ .opcode = .AND } },
        .{ .name = "ORA", .base = .{ .opcode = .ORA } },
        .{ .name = "EOR", .base = .{ .opcode = .EOR } },
        .{ .name = "SFT", .base = .{ .opcode = .SFT } },
    };

    for (opcodes) |entry| {
        if (sw(to_parse, entry.name)) {
            var inst = entry.base;
            var len: usize = entry.name.len;
            const rest = to_parse[len..];

            // Mode suffixes may appear in any order: '2', 'r', 'k'
            var i: usize = 0;
            while (i < rest.len) : (i += 1) {
                switch (rest[i]) {
                    '2' => {
                        inst.short_mode = 1;
                        len += 1;
                    },
                    'r' => {
                        inst.return_mode = 1;
                        len += 1;
                    },
                    'k' => {
                        inst.keep_mode = 1;
                        len += 1;
                    },
                    else => break,
                }
            }

            return inst.to_u8();
        }
    }

    return null;
}

fn parseLiteral(to_parse: []const u8) !u16 {
    if (to_parse.len != 4 and to_parse.len != 2)
        return AssemblerError.InvalidNumberLiteral;

    return std.fmt.parseInt(u16, to_parse, 16);
}

fn tryParseLiteral(to_parse: []const u8) ?u16 {
    return parseLiteral(to_parse) catch return null;
}

fn parseDefLabel(to_parse: []const u8) ![]const u8 {
    var label = to_parse;

    if (label.len == 0) {
        return AssemblerError.ZeroLengthLabel;
    }

    if (std.mem.find(u8, NON_LABEL_START_RUNES, label[0..1])) |i| {
        _ = i;
        return AssemblerError.InvalidDefLabel;
    } else if (label[0] == '&' or to_parse[0] == '/') {
        return AssemblerError.InvalidDefLabel;
    }

    return label;
}

fn resolveMacros(self: *Self, pre_macro_tokens: []Lexer.Token) ![]Lexer.Token {
    var macros =
        std.StringHashMap([]Lexer.Token).init(self.arena);
    var tokens = 
        try std.ArrayList(Lexer.Token).initCapacity(self.arena, 0);
    try tokens.appendSlice(self.arena, pre_macro_tokens);

    var i: usize = 0;
    while (i < tokens.items.len) {
        const token = tokens.items[i];
        switch (token) {
            .macro_label => |macro_label| {
                if (macros.contains(macro_label))
                    return AssemblerError.DuplicateLabel;

                const starting_i = i;
                var maybe_lb_i: ?usize = null;
                var maybe_rb_i: ?usize = null;

                while (i < tokens.items.len) : (i += 1) {
                    const macro_token = tokens.items[i];
                    switch (macro_token) {
                        .left_curly_brace => {
                            maybe_lb_i = i;
                        }, 
                        .right_curly_brace => {
                            if (maybe_lb_i == null)
                                return AssemblerError.UnmatchedRightMacroBracket;
                            maybe_rb_i = i;
                            break;
                        },
                        else => {}
                    }
                }

                if (maybe_rb_i == null) {
                    return AssemblerError.UnmatchedLeftMacroBracket;
                }

                if (maybe_lb_i == null) {
                    return AssemblerError.NoMacroBrackets;
                }

                const macro_tokens = 
                    try self.arena.dupe(
                        Lexer.Token,
                        tokens.items[maybe_lb_i.?+1..maybe_rb_i.?]
                    );

                try macros.put(macro_label, macro_tokens);
                try tokens.replaceRange(
                    self.arena,
                    starting_i,
                    i - starting_i + 1,
                    &[0]Lexer.Token{});

                i = starting_i;
            },

            .identifier => |identifier| {
                if (!macros.contains(identifier)) {
                    i += 1;
                    continue;
                }

                try tokens.replaceRange(
                    self.arena,
                    i,
                    1,
                    macros.get(identifier).?);
                },
                else => i += 1,
        }
    }
    return tokens.items;
}


fn resolveLabels(self: *Self) !void {
    const prev_gen_ptr = self.gen_ptr;
    defer self.gen_ptr = prev_gen_ptr;

    for (self.unresolved_labels.items) |ulabel| {
        const addr = self.labels.get(ulabel.label)
            orelse return AssemblerError.MissingLabel;
        self.gen_ptr = ulabel.gen_ptr;

        switch (ulabel.ultype) {
            .absolute => try self.writeShort(addr),
            .relative => {
                var raddr: i32 = @intCast(addr);
                raddr -= @intCast(self.gen_ptr);
                raddr -= 2;
                if (raddr < -128 or raddr > 127)
                    return AssemblerError.RelativeAddresOverFlow;

                const i8raddr: i8 = @intCast(raddr);
                const u8raddr: u8 = @bitCast(i8raddr);
                try self.writeByte(u8raddr);
            },
            .zero_page => try self.writeByte(@truncate(addr)),
            .immediate => {
                var raddr: u32 = addr;
                if (raddr < self.gen_ptr + 2) {
                    raddr += 0x10000;
                }
                raddr -= @intCast(self.gen_ptr);
                raddr -= 2;
                try self.writeShort(@truncate(raddr));
            },
        }
    }
}

pub fn assemble(self: *Self) !void {
    var lexer: Lexer = .{ .source = self.source };
    const pre_macro_tokens = try lexer.lex(self.arena);
    const tokens = try self.resolveMacros(pre_macro_tokens);

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const token = tokens[i];
        switch (token) {
            .padding => |p| {
                const label_or_addr = try self.parseLabelOrAddress(p.value);
                var addr: u16 = undefined;
                switch (label_or_addr) {
                    .addr => |paddr| {addr = paddr;},
                    .label => |label| {
                        addr = self.labels.get(label) orelse {
                            return AssemblerError.MissingLabel;
                        };
                    }
                }
                switch (p.ptype) {
                    .absolute => {
                        self.gen_ptr = addr;
                    },
                    .relative => {
                        if (self.gen_ptr > 0xFF) {
                            // NOTE: in the original implementation, relative padding runes
                            //      add the the end of a file do not emit bytes.
                            for (0..addr) |_| try self.writeByte(0);
                        } else {
                            self.gen_ptr += addr;
                        }
                    },
                }
            },
            .addressing => |addressing| {
                const label = try self.parseLabel(addressing.value);
                // std.debug.print(
                //     "Parsed addressing '{s}' ({any}-{any})\n",
                //     .{label, addressing.placement, addressing.position}
                // );

                if (addressing.placement == .literal) {
                    switch (addressing.position) {
                        .relative, .zero_page => try self.writeByte(uxn.LIT),
                        .absolute => try self.writeByte(uxn.LIT2) ,
                    }
                }

                const ultype: UnresolvedLabelType = switch (addressing.position) {
                    .relative  => .relative,
                    .absolute =>  .absolute,
                    .zero_page => .zero_page,
                };

                try self.unresolved_labels.append(self.arena, 
                    .{ 
                        .gen_ptr = @truncate(self.gen_ptr),
                        .label = label,
                        .ultype = ultype,
                    }
                );

                switch (addressing.position) {
                    .relative, .zero_page  => self.gen_ptr += 1,
                    .absolute => self.gen_ptr += 2,
                }
            },
            .comment => {
                // do noting
            },
            .immediate => |immediate| {
                switch (immediate.itype) {
                    .absolute => try self.writeByte(uxn.JMI),
                    .conditional => try self.writeByte(uxn.JCI),
                }

                const label = try self.parseLabel(immediate.value);
                const ultype: UnresolvedLabelType = .immediate;
                try self.unresolved_labels.append(self.arena, 
                    .{ 
                        .gen_ptr = @truncate(self.gen_ptr),
                        .label = label,
                        .ultype = ultype,
                    }
                );
                self.gen_ptr += 2;

            },
            .label_def => |label_def| {
                var label = try parseDefLabel(label_def.value);
                switch (label_def.ltype) {
                    .parent => {
                        self.context = getUpTo(label, "/");
                    },
                    .child => {
                        const slices = [3][]const u8{ self.context, "/", label };
                        label = try std.mem.concat(self.arena, u8, &slices);
                    }
                }
                if (self.labels.contains(label)) 
                    return AssemblerError.DuplicateLabel;
                try self.labels.put(label, @intCast(self.gen_ptr));
            },
            .left_curly_brace => {
                return AssemblerError.UnknownInput;
            },
            .macro_label => {
                return AssemblerError.UnresolvedMacro;
            },
            .number_literal => |number_literal| {
                // std.debug.print("literal '{s}' (len: {d})\n", .{number_literal, number_literal.len});
                const num = try parseLiteral(number_literal);
                switch (number_literal.len) {
                    2 => {
                        try self.writeByte(uxn.LIT);
                        try self.writeByte(@truncate(num));
                    },
                    4 => {
                        try self.writeByte(uxn.LIT2);
                        try self.writeShort(num);
                    },
                    else => unreachable
                }
            },
            .raw_string => |raw_string| {
                for (raw_string) |c| try self.writeByte(c);
            },
            .right_curly_brace => {
                const id = self.anon_id_stack.pop() 
                    orelse return AssemblerError.UnmatchedLeftAnonBracket;
                const label = 
                    try std.fmt.allocPrint(self.arena, "{{}}lambda{x:0>4}", .{id});
                
                try self.labels.put(label, @truncate(self.gen_ptr));
            },
            .identifier => |identifier| {
                if (tryParseInstruction(identifier)) |instByte| {
                    try self.writeByte(instByte);
                } else if (tryParseLiteral(identifier)) |num| {
                    switch (identifier.len) {
                        2 => try self.writeByte(@truncate(num)),
                        4 => try self.writeShort(num),
                        else => unreachable
                    }
                } else {
                    try self.writeByte(uxn.JSI);

                    const label = try parseLabel(self, identifier);
                    const ultype: UnresolvedLabelType = .immediate;
                    try self.unresolved_labels.append(self.arena, 
                        .{ 
                            .gen_ptr = @truncate(self.gen_ptr),
                            .label = label,
                            .ultype = ultype,
                        }
                    );
                    self.gen_ptr += 2;
                }
            },
        }
    }
    try self.resolveLabels();
}

pub fn rom(self: *Self) []u8 {
    return self.program[0x100..self.max_gen_ptr+1];
}


test "tokenizer general test" {
    var heap_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer heap_arena.deinit();
    const arena = heap_arena.allocator();

    // const io = std.testing.io;
    // const source_file = try std.Io.Dir.cwd().openFile(io, "hello.tal", .{});
    // const stat = try source_file.stat(io);
    // const source = try arena.alloc(u8, stat.size);
    // _ = try source_file.readPositionalAll(io, source, 0);

    var source = 
        \\ 
        \\ ( hello-world.tal )
        \\ 
        \\ |10 @Console [ &vector $2 &read $1 &pad $5 &write $1 &error $1 ]
        \\  (some comment)                    
        \\ 

        \\ |0100 ( -> )
        \\     ;greeting
        \\     &loop
        \\         LDAk .Console/write DEO
        \\         INC2 LDAk ?&loop
        \\     POP2
        \\     #80 #0f DEO
        \\ BRK
        \\ 
        \\ @greeting "Hello, 20 "Moon! 0a 00
        .*;

    var assembler: Self = try .init(arena, &source);
    try assembler.assemble();

    const test_rom = assembler.rom();

    // try std.testing.expectEqual(expected: anytype, actual: anytype)
    try std.testing.expectEqual(0x10, assembler.labels.get("Console/vector").?);
    try std.testing.expectEqual(0x12, assembler.labels.get("Console/read").?);
    try std.testing.expectEqual(0x13, assembler.labels.get("Console/pad").?);
    try std.testing.expectEqual(0x18, assembler.labels.get("Console/write").?);
    try std.testing.expectEqual(0x19, assembler.labels.get("Console/error").?);


    // const nrows = try std.math.divCeil(usize, test_rom.len, 10);
    // for (0..nrows) |row| {
    //     for (0..10) |col| {
    //         const i = row * 10 + col;
    //         if (i >= test_rom.len) break;
    //         std.debug.print("{X:0>2} ", .{test_rom[i]});
    //     }
    //     std.debug.print("\n", .{});
    // }

    try std.testing.expectEqual(uxn.LIT2, test_rom[0x00]);
    try std.testing.expectEqualSlices(u8, &[2]u8{0x01, 0x13}, test_rom[1..2+1]);
    try std.testing.expectEqual(
        (uxn.Instruction{ .opcode = .LDA, .keep_mode = 1 }).to_u8(),
        test_rom[0x03],
    );

    // std.debug.print("Unresolved Labels:\n", .{});
    // for (assembler.unresolved_labels.items) |ulabel| {
    //     std.debug.print("{any} - '{s}' - '{any}'\n", .{ulabel.gen_ptr, ulabel.label, ulabel.ultype});
    // }
}

fn writeShort(self: *Self, short: u16) !void {
    try self.writeByte(@truncate(short >> 8));
    try self.writeByte(@truncate(short >> 0));
}

fn writeByte(self: *Self, byte: u8) !void {
    if (self.gen_ptr < 0x100) {
        return AssemblerError.ZeroPageWrite;
    }
    if (self.gen_ptr >= self.program.len) {
        return AssemblerError.OverflowMemory;
    }
    self.max_gen_ptr = @max(self.gen_ptr, self.max_gen_ptr);
    self.program[self.gen_ptr] = byte;
    self.gen_ptr += 1;
}


fn allSlice(comptime T: type, slice: []const T, pred: fn (elem: T) bool) bool {
    for (slice) |elem| {
        if (!pred(elem)) return false;
    }
    return true;
}


// get up the character needle from the beginnging of the haystack but not including.
// returns full string if needle is not present.
fn getUpTo(haystack: []const u8, needle: []const u8) []const u8 {
    if (std.mem.find(u8, haystack, needle)) |pos| {
        return haystack[0..pos];
    } else {
        return haystack;
    }
}
