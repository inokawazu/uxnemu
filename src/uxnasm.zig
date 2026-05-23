const std = @import("std");
const uxn = @import("uxn.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const source_file =  try std.Io.Dir.cwd().openFile(io, "hello.tal", .{});

    const file_size = ( try source_file.stat(io) ).size;
    const source_raw = try init.gpa.alloc(u8, file_size);
    defer init.gpa.free(source_raw);

    _ = try source_file.readPositionalAll(io, source_raw, 0);
    std.debug.print("{s}\n", .{source_raw});


    // const failing = try init.gpa.alloc(u8, 0x100);
    // for (0..failing.len) |i| {failing[i] = @intCast(i);}
    // std.debug.print("{d}\n", .{failing[10]});

    var assembler: Assembler = try .init(init.gpa, init.arena.allocator(), source_raw);
    defer assembler.deinit();
    _ = try assembler.assemble();

    // var lexer: Lexer = .{ .source = source_raw};
    // var tokens = try lexer.lex(init.gpa);
    // defer tokens.deinit(init.gpa);

    // for (tokens.items) |token| {
    //     std.debug.print("{any}\n", .{token});
    // }

}

fn findNext(
    comptime T: type, haystack: []const T, 
    start_index: usize, predicate: fn (T) bool) ?usize {
    // var end_index = start_index;
    for (start_index+1..haystack.len) |i| {
        if (predicate(haystack[i])) return i;
    }
    return null;
}

fn allSlice(comptime T: type, slice: []const T, pred: fn (elem: T) bool) bool {
    for (slice) |elem| {
        if (!pred(elem)) return false;
    }
    return true;
}

// fn isHex(str: []const u8) bool {
//     for (str) |value| {
//         std.ascii.isHex()
//     }
//     return true;
// }

// std.mem.findNonePos(comptime T: type, slice: []const T, start_index: usize, values: []const T)
// std.mem.findPos(comptime T: type, haystack: []const T, start_index: usize, needle: []const T)

const AssemblerError = error {
    Unterminated,
    InvalidAddressOrLabel,
    InvalidCharacter,
    InvalidLabel,
    InvalidOpCode,
    ZeroPageWrite,
    InvalidNumberLiteral,
    MissingLabel,
};

// const AddressOrLabel = union(enum) {
//     address: u16,
//     label: []u8,
// };

const UnresolvedLabel = struct {
    label: []u8,
    raw_literal: enum {raw, literal},
    position: enum {relative, absolute, zero_page},
};

const Assembler = struct {
    source: []u8,
    pos: usize = 0,
    gen_ptr: usize = 0,
    program: std.ArrayList(u8),
    labels: std.StringHashMap(u16),
    unresolved_labels: std.AutoHashMap(usize, UnresolvedLabel),
    context: []const u8 = "top",
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator, arena: std.mem.Allocator, source: []u8) !Self {
        const program = try std.ArrayList(u8).initCapacity(gpa, 0x100);
        errdefer gpa.free(program);

        const labels = std.StringHashMap(u16).init(gpa);
        errdefer gpa.free(program);

        const unresolved_labels = 
            std.AutoHashMap(usize, UnresolvedLabel).init(gpa);
        errdefer gpa.free(unresolved_labels);

        return .{
            .source = source,
            .program = program,
            .gpa = gpa,
            .arena = arena,
            .labels = labels,
            .unresolved_labels = unresolved_labels,
        };
    }

    pub fn deinit(self: *Self) void {
        self.program.deinit(self.gpa);
        self.labels.deinit();
        self.unresolved_labels.deinit();
    }

    fn advanceToAndConsume(self: *Self, c: u8) ![]u8 {
        const starting_pos = self.pos;
        errdefer self.pos = starting_pos;

        var i: usize = self.pos + 1;
        while (i < self.source.len) : (i += 1) {
            if (self.source[i] == c) {
                self.pos = i + 1;
                return self.source[starting_pos..self.pos];
            }
        }
        return AssemblerError.Unterminated;
    }

    /// Consumes characters until a whitespace or EOF is hit, returning the slice.
    /// TODO: CHECK!!
    fn consumeName(self: *Self) ![]u8 {
        const start_pos = self.pos;
        errdefer self.pos = start_pos;

        while (self.pos < self.source.len) : (self.pos += 1) {
            const c = self.source[self.pos];
            if (!std.ascii.isAlphanumeric(c)) break;
        }

        const token = self.source[start_pos..self.pos];
        // std.debug.print("name token found: '{s}'\n", .{token});
        if (
            token.len == 0 or allSlice(u8, token, std.ascii.isHex)
            ) {
            std.debug.print("Invalid Name: '{s}'\n", .{token});
            return AssemblerError.InvalidLabel;
        }
        // TODO: check if isOpCode
        // TODO: add other checks

        return token;
    }

    /// Tries to parse the in take hexadecimal number starting at `self.pos`.
    fn consumeNumber(self: *Self) !u16 {
        const start_pos = self.pos;
        while (self.pos < self.source.len) : (self.pos += 1) {
            const c = self.source[self.pos];
            if (!std.ascii.isHex(c)) break;
        }

        const token = self.source[start_pos..self.pos];
        // std.debug.print("number token: {s}\n", .{token});

        const num = std.fmt.parseInt(u16, token, 16) 
            catch |err| {
                self.pos = start_pos;
                return err;
            };

        return num;
    }

    fn tryConsumeNumber(self: *Self) ?u16 {
        return self.consumeNumber() catch { return null; };
    }


    fn consumeLabel(self: *Self) ![]u8 {
        const start_pos = self.pos;
        errdefer self.pos = start_pos;
        _ = try self.consumeName();
        if (self.pos < self.source.len and self.source[self.pos] == '/') {
            self.pos += 1;
            _ = try self.consumeName();
        }
        return self.source[start_pos..self.pos];
    }

    // fn consumeAddressOrLabel(self: *Self) !AddressOrLabel {
    //     const starting_pos = self.pos;
    //     const address_result = self.consumeNumber();

    //     if (address_result) |address| {
    //         return .{ .address = address };
    //     }

    //     const label_result = self.consumeName();
    //     if (label_result) |label| {
    //         return .{ .label = label };
    //     } else {
    //         self.pos = starting_pos;
    //         return AssemblerError.InvalidAddressOrLabel;
    //     }
    // }

    fn tryConsumeChar(self: *Self) ?u8 {
        if (self.pos < self.source.len) {
            defer self.pos += 1;
            return self.source[self.pos];
        } else {
            return null;
        }
    }

    pub fn assemble(self: *Self) ![]u8 {
        while (self.tryConsumeChar()) |c| {
            switch (c) {
                ' ', '\t', '\n', '\r' => {},
                '(' => {_ = try self.advanceToAndConsume(')');},
                '|' => {
                    // TODO: add label
                    const addr = try self.consumeNumber();
                    self.gen_ptr = addr;
                },
                '$' => {
                    // TODO: add label
                    const rel_addr= try self.consumeNumber();
                    self.gen_ptr += rel_addr;
                },
                '@' => {
                    const parent_label = try self.consumeName();
                    self.context = parent_label;
                    try self.labels.put(parent_label, @intCast(self.gen_ptr));
                },
                '&' => {
                    const child_label = try self.consumeName();
                    const slices = [3][]const u8{self.context, "/", child_label};
                    const label = try std.mem.concat(
                        self.arena, u8, &slices
                    );
                    std.debug.print("Adding child label: '{s}'\n", .{label});
                },
                ';' => {
                    const label = try self.consumeLabel();
                    const maybe_addr = self.labels.get(label);
                    try self.writeOpCode("LIT2");
                    if (maybe_addr) |addr| { 
                        try self.writeShort(addr); 
                    } else {
                        try self.unresolved_labels.put(
                            self.gen_ptr, 
                            .{ 
                                .label = label,
                                .raw_literal = .literal,
                                .position = .absolute 
                            }
                        );
                        self.gen_ptr += 2;
                        std.debug.print("missing label {s}\n", .{label});
                    }
                },
                '.' => {
                    const label = try self.consumeLabel();
                    // std.debug.print("getting label .{s} => \"{s}\"\n", .{label, label});
                    std.debug.print("getting label: '{s}'\n", .{label});

                    try self.labels.put(label, @intCast(self.gen_ptr));
                    const maybe_addr = self.labels.get(label);

                    try self.writeOpCode("LIT");
                    if (maybe_addr) |addr| { 
                        try self.writeByte(@truncate(addr)); 
                    } else {
                        std.debug.print("missing label: '{s}'\n", .{label});
                        return AssemblerError.InvalidLabel;
                    }
                },
                '[', ']' => {}, //Ignore '[', ']'
                '?' => {
                    const qc = self.tryConsumeChar() 
                        orelse {return AssemblerError.MissingLabel;};
                    switch (qc) {
                        '&' => {
                            const label = try self.consumeName();
                            //TODO: put label addr
                            _ = label;
                        },
                    else => {return AssemblerError.InvalidLabel;}
                    }
                },
                '#' => {
                    const starting_pos = self.pos;
                    const literal = try self.consumeNumber();
                    switch (self.pos - starting_pos) {
                        2 => {try self.writeByte(@truncate(literal));},
                        4 => {try self.writeShort(literal);},
                        else => {return AssemblerError.InvalidNumberLiteral;},
                    }
                },
                '"' => {
                    while (self.pos < self.source.len) {
                        const qc = self.source[self.pos];
                        if (std.ascii.isWhitespace(qc)) {
                            break;
                        } else {
                            try self.writeByte(qc);
                            self.pos += 1;
                        }
                    }
                },
                else => { 
                    self.pos -= 1;
                    const starting_pos = self.pos;
                    if (self.tryConsumeInstruction()) |opCodeByte| {
                        try self.writeByte(opCodeByte);
                    } else if (self.tryConsumeNumber()) |num| {
                        if (self.pos - starting_pos == 2) {
                            try self.writeByte(@truncate(num));
                        } else {
                            return AssemblerError.InvalidNumberLiteral;
                        }
                    } else {
                        std.debug.print("Unknown token: '{s}'\n", .{self.peekToken()});
                        std.process.exit(1); 
                    }
                },
            }
        }
        return self.program.items;
    }

    fn peekToken(self: *Self) []u8 {
        var pos = self.pos;
        while (pos < self.source.len) : (pos += 1) {
            if (std.ascii.isWhitespace(self.source[pos])) break;
        }
        return self.source[self.pos..pos];
    }

    fn writeShort(self: *Self, short: u16) !void {
        try self.writeByte(@truncate(short >> 8));
        try self.writeByte(@truncate(short >> 0));
    }

    fn writeByte(self: *Self, byte: u8) !void {
        if (self.gen_ptr < 0x100) {return AssemblerError.ZeroPageWrite;}
        const program_pos = self.gen_ptr - 0x100;
        if (program_pos >= self.program.items.len) {
            const n_to_add = program_pos - self.program.items.len + 1;
            try self.program.appendNTimes(self.gpa, 0x00, n_to_add);
        }
        self.program.items[program_pos] = byte;
        self.gen_ptr += 1;
    }

    fn writeOpCode(self: *Self, opCode: []const u8) !void {
        var data: u8 = undefined;
        
        if (std.mem.eql(u8, opCode, "LIT2")) {
            data = uxn.LIT2;
        } else if (std.mem.eql(u8, opCode, "LIT")) {
            data = uxn.LIT;
        } else {
            return AssemblerError.InvalidOpCode;
        }

        try self.writeByte(data);
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

};



fn printKeys(comptime T: type, hm: T) !void {
    var kiter = hm.keyIterator();
    while (kiter.next()) |key| {
        std.debug.print("key: '{s}'\n", .{key.*});
    }
}


// const LexerError = error {
//     CommentError,
//     AddressError,
// };


// const Lexer = struct {
//     source: []u8,
//     position: usize = 0,


//     const Self = @This();

//     fn getComment(self: *Self) ![]u8 {
//         var endPosition = self.position;
//         while (endPosition < self.source.len) : (endPosition += 1) {
//             if (self.source[endPosition] == ')') break;
//         }
//         if (endPosition == self.source.len) {
//             return LexerError.CommentError;
//         } else {
//             return self.source[self.position..endPosition+1];
//         }
//     }

//     fn getNumber(self: *Self, comptime T: type) !T {
//         const result = findNext(
//             u8, 
//             self.source, 
//             self.position, 
//             std.ascii.isWhitespace);

//         const end_position = result orelse self.source.len;

//         defer self.position = end_position - 1;
//         return  std.fmt.parseInt(
//             T,
//             self.source[self.position..end_position], 16
//             );
//     }

//     fn lex(self: *Self, gpa: std.mem.Allocator) !std.ArrayList(Token) {
//         var tokens: std.ArrayList(Token) = try .initCapacity(gpa, 0x10);
//         errdefer tokens.deinit(gpa);

//         while (self.position < self.source.len) : (self.position += 1) {
//             const current_char = self.source[self.position];
//             if (std.ascii.isWhitespace(current_char)) {
//                 // Do nothing
//             } else if (current_char == '(') {
//                 const comment = try self.getComment();
//                 try tokens.append(gpa, .{ .comment = comment });
//             } else if (current_char == '|') {
//                 self.position += 1;
//                 try tokens.append(gpa, .{ .absolute_pad = try self.getNumber(u16) });
//             } else if (current_char == '$') {
//                 self.position += 1;
//                 try tokens.append(gpa, .{ .relative_pad = try self.getNumber(u8) });
//             } else if (current_char == '[') {
//                 try tokens.append(gpa, .left_square);
//             } else if (current_char == ']') {
//                 try tokens.append(gpa, .right_square);
//             }
//         }
//         return tokens;
//     }
// };


// const Token = union(enum) {
//     comment: []u8,
//     absolute_pad: u16,
//     relative_pad: u8,
//     left_square: void,
//     right_square: void,
//     child_label: []u8,
//     // label: LabelToken
// };

// const Message = union(enum) {
//     text: []const u8,
//     id: u32,
//     ping: void,
// };
