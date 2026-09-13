const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const gnm = @import("../gnm.zig");
const pm4 = @import("../pm4.zig");

pub const Packet = struct {
    header: pm4.Header,
    dwords: []const u32,

    pub const ReadError = error{
        Overflow,
    };

    pub fn readDword(self: Packet, index: usize) ReadError!u32 {
        if (index + 1 > self.dwords.len) {
            return error.Overflow;
        }

        const data = self.dwords[index];
        return if (builtin.cpu.arch.endian() == .little) data else @byteSwap(data);
    }

    pub fn readStruct(self: Packet, index: usize, comptime T: type) ReadError!T {
        comptime assert(@sizeOf(T) >= @sizeOf(u32));
        comptime assert(@sizeOf(T) % @sizeOf(u32) == 0);

        const struct_dwords = @sizeOf(T) / @sizeOf(u32);
        if (index + struct_dwords > self.dwords.len) {
            return error.Overflow;
        }

        var out: T = undefined;
        const out_u32: []u32 = @as([*]u32, @ptrCast(&out))[0..struct_dwords];
        const src = self.dwords[index..][0..struct_dwords];

        for (src, out_u32) |data, *o| {
            o.* = if (builtin.cpu.arch.endian() == .little) data else @byteSwap(data);
        }
        return out;
    }
};

data: []const u32,
offset: u32,

const Parser = @This();

pub fn init(data: []const u32) Parser {
    return Parser{
        .data = data,
        .offset = 0,
    };
}

fn readHeader(self: Parser) ?pm4.Header {
    if (self.offset + 1 > self.data.len)
        return null;

    const data = self.data[self.offset];
    return if (builtin.cpu.arch.endian() == .little) @bitCast(data) else @bitCast(@byteSwap(data));
}

pub const NextPacketError = error{LengthOverflow};

pub fn nextPacket(this: *Parser) NextPacketError!?Packet {
    const header = this.readHeader() orelse
        return null;

    const num_dwords = header.count + 2;

    if (this.offset + num_dwords > this.data.len) {
        return error.LengthOverflow;
    }

    defer this.offset += num_dwords;
    return Packet{
        .header = header,
        .dwords = this.data[this.offset .. this.offset + num_dwords],
    };
}

const testing = std.testing;
const test_data = @import("test_data");

test "packet parsing" {
    const cmd: []const u32 = @ptrCast(&test_data.pm4_packet);

    var parser = Parser.init(cmd);

    if (try parser.nextPacket()) |pkt| {
        try testing.expectEqual(.pkt3, pkt.header.type);
        try testing.expectEqual(.set_context_reg, pkt.header.info.pkt3.it_opcode);
    }
    if (try parser.nextPacket()) |pkt| {
        try testing.expectEqual(.pkt3, pkt.header.type);
        try testing.expectEqual(.set_context_reg, pkt.header.info.pkt3.it_opcode);
    }
}

test "bad packet parsing" {
    const cmd: []const u32 = &[_]u32{
        0xc0016900, 0x00000000, 0x00000000, 0xd0016900, 0x00000000,
    };

    var parser = Parser.init(cmd);

    if (try parser.nextPacket()) |pkt| {
        try testing.expectEqual(.pkt3, pkt.header.type);
        try testing.expectEqual(.set_context_reg, pkt.header.info.pkt3.it_opcode);
    }
    try testing.expectError(error.LengthOverflow, parser.nextPacket());
}
