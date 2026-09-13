const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const Io = std.Io;
const mem = std.mem;
const fatal = std.process.fatal;

const gnm = @import("gnm");
const gcn = gnm.gcn;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var args_it = init.minimal.args.iterate();
    // skip our path
    _ = args_it.skip();

    const file_path = args_it.next() orelse
        fatal("Please pass an input path to a GCN shader file", .{});
    const file = Io.Dir.cwd().openFile(io, file_path, .{}) catch |err| {
        fatal("Failed to open file {s} with {t}", .{ file_path, err });
    };
    defer file.close(io);

    var file_read_buf: [512]u8 = undefined;
    var file_reader = file.reader(io, &file_read_buf);

    const gcn_code = file_reader.interface.allocRemainingAlignedSentinel(
        arena,
        .unlimited,
        .@"16",
        null,
    ) catch |err| {
        fatal("Failed to read {s} with {t}", .{ file_path, err });
    };

    const usable_len = mem.alignBackward(usize, gcn_code.len, 4);
    if (usable_len != gcn_code.len) {
        try stderr.print("Warning: input file's size is not aligned to 4. File length is 0x{0x}\n", .{
            gcn_code.len,
        });
    }
    const code_words: []const u32 = @ptrCast(@alignCast(gcn_code[0..usable_len]));

    var decoder = gcn.Decoder.init(code_words);
    while (decoder.nextInstruction()) |maybe_instr| {
        const instr = maybe_instr orelse break;
        var string_buf: [256:0]u8 = undefined;
        const instr_str = instr.format(&string_buf) catch |err| {
            try stderr.print(
                "{x:08}: Failed to format instruction with {t}\n",
                .{ instr.offset, err },
            );
            continue;
        };
        try stdout.print("{x:08}: {s}\n", .{ instr.offset, instr_str });
    } else |err| {
        try stderr.print("0x{x}: Failed to decode instruction at offset with {t}\n", .{
            decoder.getCurrentOffset(),
            err,
        });
    }

    if (gcn.Analyzer.scan(arena, code_words, .{})) |analysis| {
        try stdout.print(
            \\Shader analysis:
            \\ | Num SGPRS: {}
            \\ | Num VGPRS: {}
            \\ | MRT bits: 0x{x}
            \\ | Position bits: 0x{x}
            \\ | Param bits: 0x{x}
            \\ | Number of resources: {}
            \\
        , .{
            analysis.num_sgprs,
            analysis.num_vgprs,
            analysis.mrt_bits,
            analysis.pos_bits,
            analysis.param_bits,
            analysis.resources.len,
        });

        for (analysis.resources, 0..) |rsrc, i| {
            try stdout.print(
                \\  Resource {}:
                \\   | Type: {t}
                \\   | Binding index: {?}
                \\   | Access start: {}
                \\   | Register: {}
                \\   | Length in DWORDs: {}
                \\   | Code offset: 0x{?x}
                \\   | Is written to?: {}
                \\
            , .{
                i,
                rsrc.info,
                rsrc.binding_index,
                rsrc.access_start,
                rsrc.register,
                rsrc.dword_length,
                rsrc.code_offset,
                rsrc.flags.is_written,
            });
            switch (rsrc.info) {
                .uniform_buffer => |b| try stdout.print("Buffer length: 0x{x}\n", .{b.length}),
                else => {},
            }

            var maybe_cur_chain = analysis.findAccessChain(rsrc.access_start);
            while (maybe_cur_chain) |chain| : (maybe_cur_chain = chain.getNext(analysis.access_chains)) {
                switch (chain.instruction) {
                    .dereference => try stdout.print("Chain {}: dereference\n", .{chain.id}),
                    .offset => |off| try stdout.print("Chain {}: offset by 0x{x}\n", .{ chain.id, off }),
                }
            }
        }
    } else |err| {
        try stderr.print("Failed to analyze shader with {t}\n", .{err});
    }
}
