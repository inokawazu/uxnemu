const std = @import("std");
i: usize = 0,
source: []u8,

// +----------------------+----------------------+----------------------+----------------------+
// | Padding Runes        | Number Rune          | Label Runes          | Ascii Runes          |
// +----------------------+----------------------+----------------------+----------------------+
// | | absolute           | # literal number     | @ parent             | " raw string         |
// | $ relative           |                      | & child              |                      |
// +----------------------+----------------------+----------------------+----------------------+
// | Addressing Runes     | Wrapping Runes       | Immediate Runes      | Pre-processor Runes  |
// +----------------------+----------------------+----------------------+----------------------+
// | , literal relative   | () comment           | ! jmi                | %\{} macro           |
// | . literal zero-page  | {} anonymous         | ? jci                |                      |
// | ; literal absolute   | [] ignored           |                      |                      |
// | _ = raw relative     |                      |                      |                      |
// | - = raw zero-page    |                      |                      |                      |
// | = = raw absolute     |                      |                      |                      |
// +----------------------+----------------------+----------------------+----------------------+

const Self = @This();

pub const Token = union(enum) {
    padding: Padding,
    number_literal: []const u8,
    label_def: Label,
    comment: []const u8,
    raw_string: []const u8,
    addressing: Addressing,
    immediate: Immediate,
    left_curly_brace: void,
    right_curly_brace: void,
    macro_label: []const u8,
    identifier: []const u8,
};

const Padding = struct {
    value: []const u8,
    ptype: PaddingType,
};

const PaddingType = enum {
    absolute,
    relative,
};

const Label = struct {
    ltype: LabelType,
    value: []const u8,
};

const LabelType = enum {
    parent,
    child,
};

const Addressing = struct {
    placement: MemoryType,
    position: PositionType,
    value: []const u8,
};

const MemoryType = enum { literal, raw };

const PositionType = enum {
    relative,
    zero_page,
    absolute,
};

const Immediate = struct {
    itype: ImmediateType,
    value: []const u8,
};

const ImmediateType = enum {
    absolute,
    conditional,
};

// std.mem.findPos(u8, haystack, start_index, needle)
// std.mem.findPos(comptime T: type, haystack: []const T, start_index: usize, needle: []const T)

fn tryConsumeWhiteSpace(self: *Self) bool {
    var found_ws = false;
    while (self.i < self.source.len and isWhitespace(self.source[self.i])) : (self.i += 1) found_ws = true;
    return found_ws;
}

fn tryConsumeCharacterClass(self: *Self, class: []const u8) ?u8 {
    if (self.i >= self.source.len) return null;
    for (class) |needle| {
        if (self.source[self.i] == needle) {
            self.i += 1;
            return needle;
        }
    }
    return null;
}

fn expectNoWs(self: *Self) !void {
    try self.expectNotEnd();
    if (isWhitespace(self.source[self.i])) return LexError.UnexpectedWS;
}

fn expectWSOrEnd(self: *Self) !void {
    if (self.i >= self.source.len) return;
    if (!isWhitespace(self.source[self.i])) return LexError.UnexpectedNoneWS;
}

fn expectNotEnd(self: *Self) !void {
    if (self.i >= self.source.len) return LexError.UnexpectedEnd;
}

fn findPredOrEnd(comptime T: type, haystack: []const T, start_index: usize, pred: fn (T) bool) usize {
    for (start_index..haystack.len) |i| {
        const elem = haystack[i];
        if (pred(elem)) return i;
    }
    return haystack.len;
}

fn consumeUntilWS(self: *Self) []u8 {
    const start_i = self.i;
    while (self.i < self.source.len) : (self.i += 1) {
        if (isWhitespace(self.source[self.i])) break;
    }
    return self.source[start_i..self.i];
}

fn consumeUpto(self: *Self, end: u8) ![]u8 {
    const start_i = self.i;
    while (self.i < self.source.len) : (self.i += 1) {
        if (self.source[self.i] == end) {
            return self.source[start_i..self.i];
        }
    }
    return LexError.Unterminated;
}

fn consumeChar(self: *Self, target: u8) !void {
    try self.expectNotEnd();
    if (self.source[self.i] != target) {
        return LexError.UnexpectedInput;
    }
    self.i += 1;
}

fn consumeNumber(self: *Self) ![]u8 {
    const start_i = self.i;
    while (self.i < self.source.len) : (self.i += 1) {
        if (isWhitespace(self.source[self.i])) break;
        if (!std.ascii.isHex(self.source[self.i])) {
            // self.i = start_i;
            return LexError.InvalidHexNumber;
        }
    }
    return self.source[start_i..self.i];
}

const isWhitespace = std.ascii.isWhitespace;

const LexError = error{
    InvalidHexNumber,
    UnexpectedEnd,
    UnexpectedInput,
    UnexpectedNoneWS,
    UnexpectedWS,
    // UnknownInput,
    Unterminated,
};

pub fn lex(self: *Self, arena: std.mem.Allocator) ![]Token {
    var tokens = try std.ArrayList(Token).initCapacity(arena, 0);
    while (self.i < self.source.len) {
        if (tryConsumeWhiteSpace(self)) {
            // do nothing
        } else if (self.tryConsumeCharacterClass("|$")) |ptc| {
            const pt: PaddingType = if (ptc == '|') .absolute else .relative;
            try self.expectNoWs();
            try self.expectNotEnd();
            const value = self.consumeUntilWS();
            const padding: Padding = .{ .ptype = pt, .value = value };
            try tokens.append(arena, .{ .padding = padding });
        } else if (self.tryConsumeCharacterClass("#")) |_| {
            try self.expectNoWs();
            try self.expectNotEnd();
            const value = try self.consumeNumber();
            const token: Token = .{ .number_literal = value };
            try tokens.append(arena, token);
        } else if (self.tryConsumeCharacterClass("@&")) |ltc| {
            const ltype: LabelType = if (ltc == '@') .parent else .child;
            try self.expectNoWs();
            try self.expectNotEnd();
            const value = self.consumeUntilWS();
            const label: Label = .{ .ltype = ltype, .value = value };
            try tokens.append(arena, .{ .label_def = label });
        } else if (self.tryConsumeCharacterClass("(")) |_| {
            const value = try self.consumeUpto(')');
            try self.consumeChar(')');
            const token: Token = .{ .comment = value };
            try tokens.append(arena, token);
        } else if (self.tryConsumeCharacterClass("\"")) |_| {
            try self.expectNoWs();
            try self.expectNotEnd();
            const value = self.consumeUntilWS();
            try tokens.append(arena, .{ .raw_string = value });
        } else if (self.tryConsumeCharacterClass(",.;_-=")) |ac| {
            try self.expectNoWs();
            try self.expectNotEnd();

            var addressing: Addressing = undefined;
            addressing.value = self.consumeUntilWS();
            switch (ac) {
                ',' => {
                    addressing.placement = .literal;
                    addressing.position = .relative;
                }, // LIT
                '.' => {
                    addressing.placement = .literal;
                    addressing.position = .zero_page;
                }, // LIT
                ';' => {
                    addressing.placement = .literal;
                    addressing.position = .absolute;
                }, // LIT2 (absolute)
                '_' => {
                    addressing.placement = .raw;
                    addressing.position = .relative;
                }, // raw relative byte
                '-' => {
                    addressing.placement = .raw;
                    addressing.position = .zero_page;
                }, // raw zero-page byte
                '=' => {
                    addressing.placement = .raw;
                    addressing.position = .absolute;
                }, // raw absolute short
                else => {
                    unreachable;
                },
            }
            const token: Token = .{ .addressing = addressing };
            try tokens.append(arena, token);
        } else if (self.tryConsumeCharacterClass("!?")) |imc| {
            const itype: ImmediateType = if (imc == '!') .absolute else .conditional;
            try self.expectNoWs();
            try self.expectNotEnd();
            const value = self.consumeUntilWS();
            const immediate: Immediate =
                .{ .itype = itype, .value = value };
            try tokens.append(arena, .{ .immediate = immediate });
        } else if (self.tryConsumeCharacterClass("[]")) |_| {
            // do nothing
            // left_curly_brace: void,
        } else if (self.tryConsumeCharacterClass("{")) |_| {
            try tokens.append(arena, .left_curly_brace);
            try self.expectWSOrEnd();
            // right_curly_brace: void,
        } else if (self.tryConsumeCharacterClass("}")) |_| {
            try tokens.append(arena, .right_curly_brace);
            // macro_label: []const u8,
        } else if (self.tryConsumeCharacterClass("%")) |_| {
            try self.expectNoWs();
            try self.expectNotEnd();
            const label = self.consumeUntilWS();
            try tokens.append(arena, .{ .macro_label = label });
            // identifier: []const u8,
        } else {
            const label = self.consumeUntilWS();
            try tokens.append(arena, .{ .identifier = label });
        }
    }
    return tokens.items;
}

test "tokenizer general test" {
    var source =
        \\ |100 $123 $bye |hello
        \\ #beef #1234 #FF @main @main/sub &sub
        \\ (this is a comment) (this is another !"#$%6 one  )
        \\ "hello1234()!=
        \\ ,this<is-label> =another_one
        \\ [ !{ ?/immediate-cond ]
        \\ %this-is-a-macro { ADD ADD2r main/sub }
    .*;
    var lexer: Self = .{ .source = &source };
    var heap_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer heap_arena.deinit();

    const arena = heap_arena.allocator();
    const tokens = try lexer.lex(arena);
    const expectedTokens = [_]Token{
        .{ .padding = .{ .ptype = .absolute, .value = "100" } },
        .{ .padding = .{ .ptype = .relative, .value = "123" } },
        .{ .padding = .{ .ptype = .relative, .value = "bye" } },
        .{ .padding = .{ .ptype = .absolute, .value = "hello" } },
        .{ .number_literal = "beef" },
        .{ .number_literal = "1234" },
        .{ .number_literal = "FF" },
        .{ .label_def = .{ .ltype = .parent, .value = "main" } },
        .{ .label_def = .{ .ltype = .parent, .value = "main/sub" } },
        .{ .label_def = .{ .ltype = .child, .value = "sub" } },
        .{ .comment = "this is a comment" },
        .{ .comment = "this is another !\"#$%6 one  " },
        .{ .raw_string = "hello1234()!=" },
        .{ .addressing = .{ .placement = .literal, .position = .relative, .value = "this<is-label>" } },
        .{ .addressing = .{ .placement = .raw, .position = .absolute, .value = "another_one" } },
        .{ .immediate = .{ .itype = .absolute, .value = "{" } },
        .{ .immediate = .{ .itype = .conditional, .value = "/immediate-cond" } },
        .{ .macro_label = "this-is-a-macro" },
        .left_curly_brace,
        .{ .identifier = "ADD" },
        .{ .identifier = "ADD2r" },
        .{ .identifier = "main/sub" },
        .right_curly_brace,
    };

    try std.testing.expectEqualDeep(&expectedTokens, tokens);
}
