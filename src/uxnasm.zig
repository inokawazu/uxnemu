const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const source_file =  try std.Io.Dir.cwd().openFile(io, "hello.tal", .{});

    const file_size = ( try source_file.stat(io) ).size;
    const source_raw = try init.gpa.alloc(u8, file_size);
    defer init.gpa.free(source_raw);

    _ = try source_file.readPositionalAll(io, source_raw, 0);
    std.debug.print("{s}\n", .{source_raw});

    var lexer: Lexer = .{ .source = source_raw};
    var tokens = try lexer.lex(init.gpa);
    defer tokens.deinit(init.gpa);

    for (tokens.items) |token| {
        std.debug.print("{any}\n", .{token});
    }
}

const LexerError = error {
    CommentError,
    AddressError,
};

fn findNext(
    comptime T: type, haystack: []const T, 
    start_index: usize, predicate: fn (T) bool) ?usize {
    // var end_index = start_index;
    for (start_index+1..haystack.len) |i| {
        if (predicate(haystack[i])) return i;
    }
    return null;
}

// std.mem.findNonePos(comptime T: type, slice: []const T, start_index: usize, values: []const T)
// std.mem.findPos(comptime T: type, haystack: []const T, start_index: usize, needle: []const T)

const Lexer = struct {
    source: []u8,
    position: usize = 0,


    const Self = @This();

    fn getComment(self: *Self) ![]u8 {
        var endPosition = self.position;
        while (endPosition < self.source.len) : (endPosition += 1) {
            if (self.source[endPosition] == ')') break;
        }
        if (endPosition == self.source.len) {
            return LexerError.CommentError;
        } else {
            return self.source[self.position..endPosition+1];
        }
    }

    fn getNumber(self: *Self, comptime T: type) !T {
        const result = findNext(
            u8, 
            self.source, 
            self.position, 
            std.ascii.isWhitespace);

        const end_position = result orelse self.source.len;

        defer self.position = end_position - 1;
        return  std.fmt.parseInt(
            T,
            self.source[self.position..end_position], 16
            );
    }

    fn lex(self: *Self, gpa: std.mem.Allocator) !std.ArrayList(Token) {
        var tokens: std.ArrayList(Token) = try .initCapacity(gpa, 0x10);
        errdefer tokens.deinit(gpa);

        while (self.position < self.source.len) : (self.position += 1) {
            const current_char = self.source[self.position];
            if (std.ascii.isWhitespace(current_char)) {
                // Do nothing
            } else if (current_char == '(') {
                const comment = try self.getComment();
                try tokens.append(gpa, .{ .comment = comment });
            } else if (current_char == '|') {
                self.position += 1;
                try tokens.append(gpa, .{ .absolute_pad = try self.getNumber(u16) });
            } else if (current_char == '$') {
                self.position += 1;
                try tokens.append(gpa, .{ .relative_pad = try self.getNumber(u8) });
            } else if (current_char == '[') {
                try tokens.append(gpa, .left_square);
            } else if (current_char == ']') {
                try tokens.append(gpa, .right_square);
            }
        }
        return tokens;
    }
};


const Token = union(enum) {
    comment: []u8,
    absolute_pad: u16,
    relative_pad: u8,
    left_square: void,
    right_square: void,
    child_label: []u8,
    // label: LabelToken
};

// const Message = union(enum) {
//     text: []const u8,
//     id: u32,
//     ping: void,
// };
