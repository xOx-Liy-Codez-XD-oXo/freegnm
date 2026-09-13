const std = @import("std");
const Io = std.Io;
const math = std.math;
const meta = std.meta;
const mem = std.mem;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();

const gcn = @import("../gcn.zig");

pub const Resource = struct {
    pub const Type = enum(c_int) {
        uniform_buffer = 0,
        storage_buffer = 1,
        image = 2,
        sampler = 3,
        code = 4,
    };

    binding_index: ?u16,
    access_start: AccessChain.Id,

    register: gcn.Operand.Field,
    dword_length: u8,
    code_offset: ?u32,

    flags: packed struct(u32) {
        is_written: bool = false,
        _: u31 = 0,
    },

    info: union(Type) {
        pub const BufferInfo = struct {
            length: u32,
        };

        uniform_buffer: BufferInfo,
        storage_buffer: BufferInfo,
        image: void,
        sampler: void,
        code: void,
    },
};

pub const AccessChain = struct {
    pub const Id = u64;
    pub const Type = enum {
        offset,
        dereference,
    };

    id: Id,
    next: ?Id,

    instruction: union(Type) {
        offset: u32,
        dereference: void,
    },

    pub fn getNext(self: AccessChain, chain_list: []const AccessChain) ?AccessChain {
        const next_id = self.next orelse return null;
        for (chain_list) |chain| {
            if (chain.id == next_id)
                return chain;
        }
        return null;
    }
};

resources: []const Resource,
access_chains: []const AccessChain,
accesses: ?[]Access,
next_access_index: ?Access.Id,

num_sgprs: u8,
num_vgprs: u8,
mrt_bits: u8,
pos_bits: u8,
param_bits: u32,

const Analyzer = @This();

pub const empty = Analyzer{
    .resources = &.{},
    .access_chains = &.{},
    .accesses = null,
    .next_access_index = null,
    .num_sgprs = 0,
    .num_vgprs = 0,
    .mrt_bits = 0,
    .pos_bits = 0,
    .param_bits = 0,
};

pub const ScanOptions = struct {
    external_accesses: ?[]const Access = null,
    export_accesses: bool = false,
    next_access_index: ?Access.Id = null,
};

pub const ScanError = error{
    DisasmFailed,
    InternalFailure,
} || gcn.Decoder.NextError || mem.Allocator.Error || anyerror; // TODO: get rid of anyerror

pub fn scan(
    alloc: mem.Allocator,
    code: []const u32,
    options: ScanOptions,
) ScanError!Analyzer {
    var program: Program = try .init(alloc);
    defer program.deinit(alloc);

    if (options.external_accesses) |external_accesses| {
        try program.accesses_list.appendSlice(alloc, external_accesses);
    }
    if (options.next_access_index) |idx| {
        program.next_access_index = idx;
    }

    var analysis = Analyzer.empty;

    var decoder = gcn.Decoder.init(code);
    while (try decoder.nextInstruction()) |instr| {
        if (instr.microcode == .sopp and instr.data.sopp.opcode == .s_endpgm)
            break; // end of the shader

        for (instr.srcs[0..instr.numsrcs]) |src| {
            processOperand(&analysis, src);
        }
        for (instr.dsts[0..instr.numdsts]) |dst| {
            processOperand(&analysis, dst);
        }

        switch (instr.microcode) {
            .exp => {
                const target = instr.data.exp.tgt;
                if (target.toMrtIndex()) |mrt_index| {
                    analysis.mrt_bits |= @as(u8, 1) << mrt_index;
                } else if (target.toPosIndex()) |pos_index| {
                    analysis.pos_bits |= @as(u8, 1) << pos_index;
                } else if (target.toParamIndex()) |param_index| {
                    analysis.param_bits |= @as(u32, 1) << param_index;
                }
            },
            .mimg => switch (instr.data.mimg.opcode) {
                .image_load,
                .image_load_mip,
                .image_load_pck,
                .image_load_pck_sgn,
                .image_load_mip_pck,
                .image_load_mip_pck_sgn,
                => {
                    const src_image = instr.srcs[1];
                    const dst = instr.dsts[0];

                    var image_refs_buf: [8]?Access.Reference = @splat(null);
                    const image_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &image_refs_buf, src_image);

                    _ = try program.createAccess(alloc, .{
                        .type = .{
                            .resource = .image,
                        },
                        .bit_length = dst.numbits,
                        .target_field = dst.field,
                        .sources = image_regs,
                        .byte_code_offset = instr.offset,
                    });
                },
                .image_sample,
                .image_sample_c,
                .image_sample_lz,
                .image_sample_lz_o,
                => {
                    const src_image = instr.srcs[1];
                    const src_samp = instr.srcs[2];
                    const dst = instr.dsts[0];

                    var image_refs_buf: [8]?Access.Reference = @splat(null);
                    const image_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &image_refs_buf, src_image);

                    var samp_refs_buf: [4]?Access.Reference = @splat(null);
                    const samp_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &samp_refs_buf, src_samp);

                    _ = try program.createAccess(alloc, .{
                        .type = .{
                            .resource = .image,
                        },
                        .bit_length = dst.numbits,
                        .target_field = dst.field,
                        .sources = image_regs,
                        .byte_code_offset = instr.offset,
                    });
                    _ = try program.createAccess(alloc, .{
                        .type = .{
                            .resource = .sampler,
                        },
                        .bit_length = dst.numbits,
                        .target_field = dst.field,
                        .sources = samp_regs,
                        .byte_code_offset = instr.offset,
                    });
                },
                else => {},
            },
            .mtbuf => switch (instr.data.mtbuf.opcode) {
                .tbuffer_load_format_x,
                .tbuffer_load_format_xy,
                .tbuffer_load_format_xyz,
                .tbuffer_load_format_xyzw,
                => {
                    const src_resource = instr.srcs[1];
                    const dst = instr.dsts[0];

                    var refs_buf: [4]?Access.Reference = @splat(null);
                    const src_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &refs_buf, src_resource);

                    _ = try program.createAccess(alloc, .{
                        .type = .{
                            .resource = .{ .typed_buffer = .{ .is_writable = false } },
                        },
                        .bit_length = dst.numbits + (instr.srcs[2].toConstantU32().? * 8),
                        .target_field = dst.field,
                        .sources = src_regs,
                        .byte_code_offset = instr.offset,
                    });
                },
                else => {},
            },
            .mubuf => switch (instr.data.mubuf.opcode) {
                .buffer_load_format_x,
                .buffer_load_format_xy,
                .buffer_load_format_xyz,
                .buffer_load_format_xyzw,
                => {
                    const src_resource = instr.srcs[1];
                    const dst = instr.dsts[0];

                    var refs_buf: [4]?Access.Reference = @splat(null);
                    const src_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &refs_buf, src_resource);

                    _ = try program.createAccess(alloc, .{
                        .type = .{
                            .resource = .{ .untyped_buffer = .{ .is_writable = false } },
                        },
                        .bit_length = dst.numbits + (instr.srcs[2].toConstantU32().? * 8),
                        .target_field = dst.field,
                        .sources = src_regs,
                        .byte_code_offset = instr.offset,
                    });
                },
                .buffer_store_format_x,
                .buffer_store_format_xy,
                .buffer_store_format_xyz,
                .buffer_store_format_xyzw,
                => {
                    const src0 = instr.srcs[0];
                    const src_resource = instr.srcs[2];

                    var refs_buf: [4]?Access.Reference = @splat(null);
                    const src_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &refs_buf, src_resource);

                    _ = try program.createAccess(alloc, .{
                        .type = .{
                            .resource = .{ .untyped_buffer = .{ .is_writable = true } },
                        },
                        .bit_length = src0.numbits + (instr.srcs[3].toConstantU32().? * 8),
                        .target_field = src_resource.field,
                        .sources = src_regs,
                        .byte_code_offset = instr.offset,
                    });
                },
                else => {},
            },
            .smrd => switch (instr.data.smrd.opcode) {
                .s_buffer_load_dword,
                .s_buffer_load_dwordx2,
                .s_buffer_load_dwordx4,
                .s_buffer_load_dwordx8,
                .s_buffer_load_dwordx16,
                => {
                    const src = instr.srcs[0];
                    const dst = instr.dsts[0];

                    var refs_buf: [4]?Access.Reference = @splat(null);
                    const src_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &refs_buf, src);
                    const offset = instr.srcs[1].toConstantU32().?;

                    const new_access = try program.createAccess(alloc, .{
                        .type = .{
                            .resource = .{ .uniform_buffer = .{ .memory_offset = offset } },
                        },
                        .bit_length = dst.numbits,
                        .target_field = dst.field,
                        .sources = src_regs,
                        .byte_code_offset = instr.offset,
                    });
                    try program.setSgprs(dst.field, new_access);
                },
                .s_load_dword,
                .s_load_dwordx2,
                .s_load_dwordx4,
                .s_load_dwordx8,
                .s_load_dwordx16,
                => {
                    const src = instr.srcs[0];
                    const dst = instr.dsts[0];

                    var refs_buf: [4]?Access.Reference = @splat(null);
                    const src_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &refs_buf, src);
                    const offset = instr.srcs[1].toConstantU32().?;

                    const new_access = try program.createAccess(alloc, .{
                        .type = .{
                            .resource = .{ .untyped_memory = .{ .access_offset = offset } },
                        },
                        .bit_length = dst.numbits,
                        .target_field = dst.field,
                        .sources = src_regs,
                        .byte_code_offset = instr.offset,
                    });
                    try program.setSgprs(dst.field, new_access);
                },
                else => {},
            },
            .sop1 => switch (instr.data.sop1.opcode) {
                .s_mov_b32 => {
                    const src = instr.srcs[0];
                    const dst = instr.dsts[0];

                    // TODO: how should constants be handled?
                    // TODO: handle non-SGPR dst
                    if (src.toConstantU32() == null and dst.field.toSgprIndex() != null) {
                        var refs_buf: [4]?Access.Reference = @splat(null);
                        const src_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &refs_buf, src);

                        const new_access = try program.createAccess(alloc, .{
                            .type = .{
                                .register = src.field,
                            },
                            .bit_length = dst.numbits,
                            .target_field = dst.field,
                            .sources = src_regs,
                            .byte_code_offset = instr.offset,
                        });
                        try program.setSgprs(dst.field, new_access);
                    }
                },
                .s_swappc_b64 => {
                    const src = instr.srcs[0];
                    const dst = instr.dsts[0];

                    var refs_buf: [4]?Access.Reference = @splat(null);
                    const src_regs = try program.findAndBuildOptimizedSrcAccesses(alloc, &refs_buf, src);

                    const new_access = try program.createAccess(alloc, .{
                        .type = .{ .resource = .{
                            .code = {},
                        } },
                        .bit_length = dst.numbits,
                        .target_field = dst.field,
                        .sources = src_regs,
                        .byte_code_offset = instr.offset,
                    });
                    try program.setSgprs(dst.field, new_access);
                },
                else => {},
            },
            else => {},
        }
    }

    var next_binding_index: u16 = 0;

    for (program.accesses_list.items) |access| {
        if (access.type != .resource)
            continue;
        switch (access.type.resource) {
            .typed_buffer,
            .untyped_buffer,
            => |buf| {
                const buf_byte_len = access.bit_length / 8;

                const access_info = try program.walkAndWriteAccesses(alloc, access.sources[0], .{
                    .deref_last_source = false,
                });

                if (program.findExistingResource(access_info.access_start_index, .storage_buffer)) |rsrc| {
                    program.releaseLastWriteAccesses(access_info.num_chains_created);
                    rsrc.info.storage_buffer.length = @max(rsrc.info.storage_buffer.length, buf_byte_len);
                } else {
                    const src = program.findAccess(access.sources[0].?.access_id).?;
                    const index: gcn.Operand.Field = switch (src.type) {
                        .user_data => |idx| @fromBackingInt(@intCast(@backingInt(gcn.Operand.Field.sgpr_0) + idx)),
                        .register => |reg| reg,
                        .resource => src.target_field,
                    };

                    try program.rsrc_list.append(alloc, Resource{
                        .binding_index = next_binding_index,
                        .access_start = access_info.access_start_index,

                        .register = index,
                        .dword_length = 4,
                        .code_offset = access.byte_code_offset,

                        .flags = .{ .is_written = buf.is_writable },
                        .info = .{ .storage_buffer = .{ .length = buf_byte_len } },
                    });

                    next_binding_index += 1;
                }
            },
            .uniform_buffer,
            => |ubo| {
                const src1_offset = ubo.memory_offset;
                const buf_byte_len = src1_offset + (access.bit_length / 8);

                const access_info = try program.walkAndWriteAccesses(alloc, access.sources[0], .{
                    .deref_last_source = false,
                });

                if (program.findExistingResource(access_info.access_start_index, .uniform_buffer)) |rsrc| {
                    program.releaseLastWriteAccesses(access_info.num_chains_created);
                    rsrc.info.uniform_buffer.length = @max(rsrc.info.uniform_buffer.length, buf_byte_len);
                } else {
                    const src = program.findAccess(access.sources[0].?.access_id).?;
                    const index: gcn.Operand.Field = switch (src.type) {
                        .user_data => |idx| @fromBackingInt(@intCast(@backingInt(gcn.Operand.Field.sgpr_0) + idx)),
                        .register => |reg| reg,
                        .resource => src.target_field,
                    };

                    try program.rsrc_list.append(alloc, Resource{
                        .binding_index = next_binding_index,
                        .access_start = access_info.access_start_index,

                        .register = index,
                        .dword_length = 4,
                        .code_offset = access.byte_code_offset,

                        .flags = .{},
                        .info = .{ .uniform_buffer = .{ .length = buf_byte_len } },
                    });

                    next_binding_index += 1;
                }
            },
            .image,
            => {
                const access_info = try program.walkAndWriteAccesses(alloc, access.sources[0], .{
                    .deref_last_source = false,
                });

                if (program.findExistingResource(access_info.access_start_index, .image) != null) {
                    program.releaseLastWriteAccesses(access_info.num_chains_created);
                } else {
                    const src = program.findAccess(access.sources[0].?.access_id).?;
                    const index: gcn.Operand.Field = switch (src.type) {
                        .user_data => |idx| @fromBackingInt(@intCast(@backingInt(gcn.Operand.Field.sgpr_0) + idx)),
                        .register => |reg| reg,
                        .resource => src.target_field,
                    };

                    try program.rsrc_list.append(alloc, Resource{
                        .binding_index = next_binding_index,
                        .access_start = access_info.access_start_index,

                        .register = index,
                        .dword_length = 8,
                        .code_offset = access.byte_code_offset,

                        .flags = .{},
                        .info = .{ .image = {} },
                    });

                    next_binding_index += 1;
                }
            },
            .sampler,
            => {
                const access_info = try program.walkAndWriteAccesses(alloc, access.sources[0], .{
                    .deref_last_source = false,
                });

                if (program.findExistingResource(access_info.access_start_index, .sampler) != null) {
                    program.releaseLastWriteAccesses(access_info.num_chains_created);
                } else {
                    const src = program.findAccess(access.sources[0].?.access_id).?;
                    const index: gcn.Operand.Field = switch (src.type) {
                        .user_data => |idx| @fromBackingInt(@intCast(@backingInt(gcn.Operand.Field.sgpr_0) + idx)),
                        .register => |reg| reg,
                        .resource => src.target_field,
                    };

                    try program.rsrc_list.append(alloc, Resource{
                        .binding_index = next_binding_index,
                        .access_start = access_info.access_start_index,

                        .register = index,
                        .dword_length = 4,
                        .code_offset = access.byte_code_offset,

                        .flags = .{},
                        .info = .{ .sampler = {} },
                    });

                    next_binding_index += 1;
                }
            },
            .code => {
                const access_info = try program.walkAndWriteAccesses(alloc, access.sources[0], .{
                    .deref_last_source = true,
                });

                if (program.findExistingResource(access_info.access_start_index, .code) != null) {
                    program.releaseLastWriteAccesses(access_info.num_chains_created);
                } else {
                    const src = program.findAccess(access.sources[0].?.access_id).?;
                    const index: gcn.Operand.Field = switch (src.type) {
                        .user_data => |idx| @fromBackingInt(@intCast(@backingInt(gcn.Operand.Field.sgpr_0) + idx)),
                        .register => |reg| reg,
                        .resource => src.target_field,
                    };

                    try program.rsrc_list.append(alloc, Resource{
                        .binding_index = null,
                        .access_start = access_info.access_start_index,

                        .register = index,
                        .dword_length = 2,
                        .code_offset = access.byte_code_offset,

                        .flags = .{},
                        .info = .{ .code = {} },
                    });
                }
            },
            else => {},
        }
    }

    analysis.resources = try program.rsrc_list.toOwnedSlice(alloc);
    errdefer alloc.free(analysis.resources);
    analysis.access_chains = try program.chains_list.toOwnedSlice(alloc);
    errdefer alloc.free(analysis.access_chains);

    if (options.export_accesses) {
        analysis.accesses = try program.accesses_list.toOwnedSlice(alloc);
        errdefer alloc.free(analysis.accesses);
        analysis.next_access_index = program.next_access_index;
    }
    return analysis;
}

pub fn deinit(self: *Analyzer, alloc: mem.Allocator) void {
    alloc.free(self.resources);
    alloc.free(self.access_chains);
    if (self.accesses) |acc| {
        alloc.free(acc);
    }
}

inline fn processOperand(analysis: *Analyzer, op: gcn.Operand) void {
    if (op.field.toSgprIndex()) |sgpr_index| {
        analysis.num_sgprs = @truncate(@max(sgpr_index + (op.numbits / 32), analysis.num_sgprs));
    } else if (op.field.toVgprIndex()) |vgpr_index| {
        analysis.num_vgprs = @truncate(@max(vgpr_index + (op.numbits / 32), analysis.num_vgprs));
    }
}

pub fn accessResource(
    self: gcn.Analyzer,
    rsrc: gcn.Analyzer.Resource,
    ud: []const u32,
) ![*]const u32 {
    var maybe_cur_chain: ?AccessChain = res: {
        for (self.access_chains) |chain| {
            if (chain.id == rsrc.access_start)
                break :res chain;
        }
        return error.ResourceInvalidChainId;
    };

    // TODO: memory bound checks on cur_ud
    var cur_ud: u64 = @intFromPtr(ud.ptr);
    while (maybe_cur_chain) |cur_chain| : (maybe_cur_chain = cur_chain.getNext(self.access_chains)) {
        switch (cur_chain.instruction) {
            .dereference => {
                const address_ptr: *align(4) const u64 = @ptrFromInt(cur_ud);
                const raw_address = address_ptr.*;
                const address = if (native_endian == .little) raw_address else @byteSwap(raw_address);
                const real_address = address & 0xf_ffff_ffff_ffff;
                cur_ud = real_address;
            },
            .offset => |off| cur_ud += off,
        }
    }

    return @ptrFromInt(cur_ud);
}

pub fn findAccessChain(self: Analyzer, id: AccessChain.Id) ?AccessChain {
    for (self.access_chains) |*chain| {
        if (chain.id == id)
            return chain.*;
    }
    return null;
}

pub const Access = struct {
    pub const Id = u56;
    const Type = enum {
        user_data,
        register,
        resource,
    };
    const TypeInfo = union(Type) {
        const StorageBufferInfo = struct {
            is_writable: bool,
        };

        user_data: u4,
        register: gcn.Operand.Field,
        resource: union(ResourceType) {
            untyped_memory: struct {
                access_offset: u32,
            },
            code: void,
            typed_buffer: StorageBufferInfo,
            untyped_buffer: StorageBufferInfo,
            uniform_buffer: struct {
                memory_offset: u32,
            },
            image: void,
            sampler: void,
        },
    };
    const ResourceType = enum {
        untyped_memory,
        code,
        typed_buffer,
        untyped_buffer,
        uniform_buffer,
        image,
        sampler,
    };

    const Reference = struct {
        access_id: Id,
        index_into_access: u7,
    };

    id: Id,
    type: TypeInfo,
    bit_length: u32,

    target_field: gcn.Operand.Field,

    sources: [8]?Access.Reference,
    num_sources: u4,

    byte_code_offset: ?u32,

    pub fn format(
        self: Access,
        writer: *Io.Writer,
    ) !void {
        const acc_type = switch (self.type) {
            .resource => |rsrc| @tagName(rsrc),
            else => @tagName(self.type),
        };

        try writer.print("%{d} = access_{s}(.{{", .{ self.id, acc_type });

        for (self.sources[0..self.num_sources], 0..) |maybe_src, i| {
            if (i > 0)
                try writer.writeAll(", ");

            if (maybe_src) |src|
                try writer.print("%{d}[{d}]", .{ src.access_id, src.index_into_access })
            else
                try writer.writeAll("UNDEFINED_VAR");
        }

        try writer.writeAll("}}");

        switch (self.type) {
            .resource => |rsrc_type| switch (rsrc_type) {
                .untyped_memory => |m| try writer.print(", access_offset = 0x{x}", .{m.access_offset}),
                .uniform_buffer => |buf| try writer.print(", memory_offset = 0x{x}", .{buf.memory_offset}),
                else => {},
            },
            else => {},
        }

        try writer.writeAll(");");

        if (self.byte_code_offset) |code_offset| {
            try writer.print(" // @ 0x{x}", .{code_offset});
        } else {
            try writer.writeAll(" // external");
        }
    }
};

const Program = struct {
    const NUM_SGPRS = @backingInt(gcn.Operand.Field.sgpr_103) +
        @backingInt(gcn.Operand.Field.sgpr_0) +
        1;
    const NUM_USERDATA_SGPRS = 16;

    accesses_list: ArrayListUnmanaged(Access),
    next_access_index: Access.Id,
    next_chain_index: u64,

    sgprs: [NUM_SGPRS]?Access.Reference,

    rsrc_list: ArrayListUnmanaged(Resource),
    chains_list: ArrayListUnmanaged(AccessChain),

    fn init(alloc: mem.Allocator) !Program {
        var prog = Program{
            .accesses_list = .empty,
            .next_access_index = 0,
            .next_chain_index = 0,
            .sgprs = @splat(null),
            .rsrc_list = .empty,
            .chains_list = .empty,
        };
        errdefer prog.accesses_list.deinit(alloc);
        errdefer prog.rsrc_list.deinit(alloc);
        errdefer prog.chains_list.deinit(alloc);

        for (prog.sgprs[0..NUM_USERDATA_SGPRS], 0..) |*reg, i| {
            const ud_access = try prog.createAccess(alloc, .{
                .type = .{
                    .user_data = @truncate(i),
                },
                .bit_length = 32,
                .target_field = @fromBackingInt(@intCast(i)),
                .sources = &.{},
                .byte_code_offset = null,
            });
            reg.* = Access.Reference{
                .access_id = ud_access.id,
                .index_into_access = 0,
            };
        }

        return prog;
    }

    fn deinit(self: *Program, alloc: mem.Allocator) void {
        self.accesses_list.deinit(alloc);
        self.rsrc_list.deinit(alloc);
        self.chains_list.deinit(alloc);
    }

    fn setSgprs(
        self: *Program,
        start_register: gcn.Operand.Field,
        access: *Access,
    ) !void {
        const start_index = start_register.toSgprIndex() orelse
            return error.NotAnSgpr;

        const access_dwords = access.bit_length / 32;
        if (start_index + access_dwords >= NUM_SGPRS)
            return error.SgprOutOfBounds;

        for (0..access_dwords) |i| {
            self.sgprs[start_index + i] = .{
                .access_id = access.id,
                .index_into_access = @truncate(i),
            };
        }
    }

    fn getSgprs(
        self: Program,
        registers_buf: []?Access.Reference,
        start_register: gcn.Operand.Field,
        num_registers: u7,
    ) ![]?Access.Reference {
        const start_index = start_register.toSgprIndex() orelse
            return error.NotAnSgpr;
        if (start_index + num_registers >= NUM_SGPRS)
            return error.SgprOutOfBounds;

        const maybe_first_reg = self.sgprs[start_index];
        if (maybe_first_reg) |first_reg| {
            if (self.findAccess(first_reg.access_id)) |first_acc| {
                const all_registers_bits = num_registers * @as(u32, 32);
                if (first_reg.index_into_access == 0 and
                    first_acc.bit_length >= all_registers_bits)
                {
                    registers_buf[0] = first_reg;
                    return registers_buf[0..1];
                }
            }
        }

        for (0..num_registers) |i| {
            registers_buf[i] = self.sgprs[start_index + i];
        }
        return registers_buf[0..num_registers];
    }

    fn findAccess(self: Program, id: Access.Id) ?*Access {
        for (self.accesses_list.items) |*acc| {
            if (acc.id == id)
                return acc;
        }
        return null;
    }

    fn createAccess(
        self: *Program,
        alloc: mem.Allocator,
        params: struct {
            type: Access.TypeInfo,
            bit_length: u32,
            target_field: gcn.Operand.Field,
            sources: []const ?Access.Reference,
            byte_code_offset: ?u32,
        },
    ) !*Access {
        const num_sources = math.cast(u4, params.sources.len) orelse
            return error.TooManySources;

        var sources_array: [8]?Access.Reference = @splat(null);
        for (sources_array[0..params.sources.len], params.sources) |*dst, src| {
            dst.* = src;
        }

        const new_access = try self.accesses_list.addOne(alloc);
        errdefer self.accesses_list.pop();

        new_access.* = .{
            .id = self.next_access_index,
            .type = params.type,
            .bit_length = params.bit_length,
            .target_field = params.target_field,
            .sources = sources_array,
            .num_sources = num_sources,
            .byte_code_offset = params.byte_code_offset,
        };
        self.next_access_index += 1;

        return new_access;
    }

    fn findAndBuildOptimizedSrcAccesses(
        self: *Program,
        alloc: mem.Allocator,
        refs_buf: []?Access.Reference,
        src: gcn.Operand,
    ) ![]?Access.Reference {
        const src_dwords: u7 = @truncate(src.numbits / 32);
        const new_srcs = try self.getSgprs(refs_buf, src.field, @truncate(src_dwords)); // s[28:31]
        for (new_srcs) |*maybe_src_reg| {
            if (maybe_src_reg.*) |src_reg| {
                if (self.findAccess(src_reg.access_id)) |src_acc| {
                    switch (src_acc.type) {
                        .register => |base_reg| {
                            if (src_reg.index_into_access > 0) {
                                _ = base_reg;
                                @panic("TODO");
                            } else {
                                maybe_src_reg.* = src_acc.sources[0];
                            }
                        },
                        .resource => |rsrc_type| switch (rsrc_type) {
                            .untyped_memory => |m| {
                                if (src_reg.index_into_access > 0) {
                                    const base_reg = src_acc.target_field.toSgprIndex() orelse
                                        return error.SrcAccessNotIndexable;
                                    const actual_reg = base_reg + src_reg.index_into_access;
                                    const new_sub_acc = try self.createAccess(alloc, .{
                                        .type = .{
                                            .resource = .{ .untyped_memory = .{
                                                .access_offset = m.access_offset +
                                                    (src_reg.index_into_access * 4),
                                            } },
                                        },
                                        .bit_length = src.numbits,
                                        .target_field = @fromBackingInt(@intCast(actual_reg)),
                                        .sources = src_acc.sources[0..src_acc.num_sources],
                                        .byte_code_offset = null,
                                    });
                                    maybe_src_reg.* = Access.Reference{
                                        .access_id = new_sub_acc.id,
                                        .index_into_access = 0,
                                    };
                                }
                            },
                            else => {},
                        },
                        else => {},
                    }
                }
            }
        }
        return new_srcs;
    }

    const WalkAndWriteAccessesOptions = struct {
        deref_last_source: bool,
    };

    const WalkAndWriteAccessesResult = struct {
        access_start_index: AccessChain.Id,
        num_chains_created: usize,
    };

    fn walkAndWriteAccesses(
        self: *Program,
        alloc: mem.Allocator,
        maybe_start_src: ?Access.Reference,
        options: WalkAndWriteAccessesOptions,
    ) !WalkAndWriteAccessesResult {
        var num_chains_created: usize = 0;

        var maybe_cur_src = maybe_start_src;
        var last_offset_index: ?u64 = null;
        while (maybe_cur_src) |cur_src| {
            const cur_src_acc = self.findAccess(cur_src.access_id).?;

            const offset = switch (cur_src_acc.type) {
                .user_data => |ud_idx| ud_idx * @as(u32, 4),
                .resource => |rsrc_type| switch (rsrc_type) {
                    .untyped_memory => |m| m.access_offset,
                    .uniform_buffer => |buf| buf.memory_offset,
                    else => @panic("TODO"),
                },
                else => @panic("TODO"),
            };

            const maybe_deref_index = if (!meta.eql(cur_src, maybe_start_src.?) or
                options.deref_last_source)
            res: {
                const deref_index = self.next_chain_index;
                self.next_chain_index += 1;

                try self.chains_list.append(alloc, AccessChain{
                    .id = deref_index,
                    .next = last_offset_index,
                    .instruction = .{ .dereference = {} },
                });

                num_chains_created += 1;
                break :res deref_index;
            } else null;

            const offset_index = self.next_chain_index;
            self.next_chain_index += 1;

            try self.chains_list.append(alloc, AccessChain{
                .id = offset_index,
                .next = maybe_deref_index,
                .instruction = .{ .offset = offset },
            });
            num_chains_created += 1;

            last_offset_index = offset_index;
            maybe_cur_src = cur_src_acc.sources[0];
        }

        return WalkAndWriteAccessesResult{
            .access_start_index = last_offset_index.?,
            .num_chains_created = num_chains_created,
        };
    }

    fn releaseLastWriteAccesses(self: *Program, num_chains_created: usize) void {
        for (0..num_chains_created) |_| {
            _ = self.chains_list.pop();
        }
        self.next_chain_index -= num_chains_created;
    }

    fn findExistingResource(
        self: Program,
        maybe_start_chain_id: ?AccessChain.Id,
        res_type: Resource.Type,
    ) ?*Resource {
        const start_chain_id = maybe_start_chain_id orelse
            return null;
        const maybe_start_chain = self.findAccessChain(start_chain_id);
        for (self.rsrc_list.items) |*rsrc| start_rsrc: {
            const maybe_other_chain = self.findAccessChain(rsrc.access_start);

            var maybe_cur_other_chain = maybe_other_chain;
            var maybe_cur_chain = maybe_start_chain;
            while (maybe_cur_chain) |cur_chain| : (maybe_cur_chain = cur_chain.getNext(self.chains_list.items)) {
                var cur_other_chain = maybe_cur_other_chain orelse
                    break :start_rsrc;

                if (!meta.eql(cur_chain.instruction, cur_other_chain.instruction)) {
                    break :start_rsrc;
                }

                maybe_cur_other_chain = cur_other_chain.getNext(self.chains_list.items);
            }

            if (rsrc.info != res_type) {
                break :start_rsrc;
            }
            return rsrc;
        }
        return null;
    }

    fn findAccessChain(self: Program, id: u64) ?AccessChain {
        for (self.chains_list.items) |chain| {
            if (chain.id == id)
                return chain;
        }
        return null;
    }
};

const testing = std.testing;

test "analyze fetch" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_fetch.gcn");

    var analysis = try Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(8, analysis.num_sgprs);
    try testing.expectEqual(10, analysis.num_vgprs);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // binding 0
        .{ .id = 0, .next = null, .instruction = .{ .offset = 0 } },
        .{ .id = 1, .next = 0, .instruction = .{ .dereference = {} } },
        .{ .id = 2, .next = 1, .instruction = .{ .offset = 8 } },
        // binding 1
        .{ .id = 3, .next = null, .instruction = .{ .offset = 16 } },
        .{ .id = 4, .next = 3, .instruction = .{ .dereference = {} } },
        .{ .id = 5, .next = 4, .instruction = .{ .offset = 8 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = 0,
            .access_start = 2,
            .register = .sgpr_4,
            .dword_length = 4,
            .code_offset = 0x8,
            .flags = .{},
            .info = .{ .storage_buffer = .{ .length = 12 } },
        },
        .{
            .binding_index = 1,
            .access_start = 5,
            .register = .sgpr_4,
            .dword_length = 4,
            .code_offset = 0x18,
            .flags = .{},
            .info = .{ .storage_buffer = .{ .length = 8 } },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze vs" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_vs.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(56, analysis.num_sgprs);
    try testing.expectEqual(16, analysis.num_vgprs);
    try testing.expectEqual(0x1, analysis.pos_bits);
    try testing.expectEqual(0x7, analysis.param_bits);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // code pointer 0
        .{ .id = 0, .next = null, .instruction = .{ .dereference = {} } },
        .{ .id = 1, .next = 0, .instruction = .{ .offset = 0 } },
        // binding 0
        .{ .id = 2, .next = null, .instruction = .{ .offset = 16 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = null,
            .access_start = 1,
            .register = .sgpr_0,
            .dword_length = 2,
            .code_offset = 0x8,
            .flags = .{},
            .info = .{ .code = {} },
        },
        .{
            .binding_index = 0,
            .access_start = 2,
            .register = .sgpr_4,
            .dword_length = 4,
            .code_offset = 0xc,
            .flags = .{},
            .info = .{ .uniform_buffer = .{ .length = 0xc0 } },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze ps" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_ps.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(37, analysis.num_sgprs);
    try testing.expectEqual(20, analysis.num_vgprs);
    try testing.expectEqual(0x1, analysis.mrt_bits);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // binding 0
        .{ .id = 0, .next = null, .instruction = .{ .offset = 48 } },
        // binding 1
        .{ .id = 1, .next = null, .instruction = .{ .offset = 0 } },
        // binding 2
        .{ .id = 2, .next = null, .instruction = .{ .offset = 32 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = 0,
            .access_start = 0,
            .register = .sgpr_12,
            .dword_length = 4,
            .code_offset = 0xc,
            .flags = .{},
            .info = .{ .uniform_buffer = .{ .length = 0xd0 } },
        },
        .{
            .binding_index = 1,
            .access_start = 1,
            .register = .sgpr_0,
            .dword_length = 8,
            .code_offset = 0x204,
            .flags = .{},
            .info = .{ .image = {} },
        },
        .{
            .binding_index = 2,
            .access_start = 2,
            .register = .sgpr_8,
            .dword_length = 4,
            .code_offset = 0x204,
            .flags = .{},
            .info = .{ .sampler = {} },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze vs2" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_vs2.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(16, analysis.num_sgprs);
    try testing.expectEqual(10, analysis.num_vgprs);
    try testing.expectEqual(0x1, analysis.pos_bits);
    try testing.expectEqual(0x1, analysis.param_bits);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // code pointer 0
        .{ .id = 0, .next = null, .instruction = .{ .dereference = {} } },
        .{ .id = 1, .next = 0, .instruction = .{ .offset = 0 } },
        // binding 0
        .{ .id = 2, .next = null, .instruction = .{ .offset = 0 } },
        .{ .id = 3, .next = 2, .instruction = .{ .dereference = {} } },
        .{ .id = 4, .next = 3, .instruction = .{ .offset = 24 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = null,
            .access_start = 1,
            .register = .sgpr_0,
            .dword_length = 2,
            .code_offset = 0x0,
            .flags = .{},
            .info = .{ .code = {} },
        },
        .{
            .binding_index = 0,
            .access_start = 4,
            .register = .sgpr_0,
            .dword_length = 4,
            .code_offset = 0xc,
            .flags = .{},
            .info = .{ .uniform_buffer = .{ .length = 0x40 } },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze ps clear" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_ps_clear.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(4, analysis.num_sgprs);
    try testing.expectEqual(2, analysis.num_vgprs);
    try testing.expectEqual(0x1, analysis.mrt_bits);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // binding 0
        .{ .id = 0, .next = null, .instruction = .{ .offset = 0 } },
        .{ .id = 1, .next = 0, .instruction = .{ .dereference = {} } },
        .{ .id = 2, .next = 1, .instruction = .{ .offset = 0 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = 0,
            .access_start = 2,
            .register = .sgpr_0,
            .dword_length = 4,
            .code_offset = 8,
            .flags = .{},
            .info = .{ .uniform_buffer = .{ .length = 0x10 } },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze VS code ptr" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/vtx_code_ptr.gcn");
    const fetch_code align(@alignOf(u32)) = @embedFile("data/vtx_fetch.gcn");

    // find base shader's resources
    var base_analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{
        .export_accesses = true,
    });
    defer base_analysis.deinit(alloc);

    // find all function pointers in base shader,
    // and make a list of all code-only resources
    var maybe_code_accesses: ?[]gcn.Analyzer.Access = null;
    defer if (maybe_code_accesses) |accesss| alloc.free(accesss);

    for (base_analysis.resources) |rsrc| {
        if (rsrc.info != .code)
            continue;

        // append its resources to the base shader
        var func_analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(fetch_code)), .{
            .external_accesses = maybe_code_accesses,
            .export_accesses = true,
        });
        defer func_analysis.deinit(alloc);

        if (maybe_code_accesses) |accesses| {
            alloc.free(accesses);
        }
        maybe_code_accesses = func_analysis.accesses.?;
        func_analysis.accesses = null;
    }

    // perform the full analysis with code-only resources AND the base shader
    var full_analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{
        .external_accesses = maybe_code_accesses.?,
    });
    defer full_analysis.deinit(alloc);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // binding 0
        .{ .id = 0, .next = null, .instruction = .{ .offset = 0 } },
        .{ .id = 1, .next = 0, .instruction = .{ .dereference = {} } },
        .{ .id = 2, .next = 1, .instruction = .{ .offset = 8 } },
        // binding 1
        .{ .id = 3, .next = null, .instruction = .{ .offset = 16 } },
        .{ .id = 4, .next = 3, .instruction = .{ .dereference = {} } },
        .{ .id = 5, .next = 4, .instruction = .{ .offset = 8 } },
        // binding 2
        .{ .id = 6, .next = null, .instruction = .{ .offset = 32 } },
        .{ .id = 7, .next = 6, .instruction = .{ .dereference = {} } },
        .{ .id = 8, .next = 7, .instruction = .{ .offset = 8 } },
        // binding 3
        .{ .id = 9, .next = null, .instruction = .{ .offset = 48 } },
        .{ .id = 10, .next = 9, .instruction = .{ .dereference = {} } },
        .{ .id = 11, .next = 10, .instruction = .{ .offset = 8 } },
        // code pointer 0
        .{ .id = 12, .next = null, .instruction = .{ .dereference = {} } },
        .{ .id = 13, .next = 12, .instruction = .{ .offset = 0 } },
        // binding 4
        .{ .id = 14, .next = null, .instruction = .{ .offset = 16 } },
        .{ .id = 15, .next = 14, .instruction = .{ .dereference = {} } },
        .{ .id = 16, .next = 15, .instruction = .{ .offset = 8 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = 0,
            .access_start = 2,
            .register = .sgpr_12,
            .dword_length = 4,
            .code_offset = 0x14,
            .flags = .{},
            .info = .{ .storage_buffer = .{ .length = 16 } },
        },
        .{
            .binding_index = 1,
            .access_start = 5,
            .register = .sgpr_16,
            .dword_length = 4,
            .code_offset = 0x1c,
            .flags = .{},
            .info = .{ .storage_buffer = .{ .length = 16 } },
        },
        .{
            .binding_index = 2,
            .access_start = 8,
            .register = .sgpr_20,
            .dword_length = 4,
            .code_offset = 0x24,
            .flags = .{},
            .info = .{ .storage_buffer = .{ .length = 16 } },
        },
        .{
            .binding_index = 3,
            .access_start = 11,
            .register = .sgpr_24,
            .dword_length = 4,
            .code_offset = 0x2c,
            .flags = .{},
            .info = .{ .storage_buffer = .{ .length = 16 } },
        },
        .{
            .binding_index = null,
            .access_start = 13,
            .register = .sgpr_0,
            .dword_length = 2,
            .code_offset = 0,
            .flags = .{},
            .info = .{ .code = {} },
        },
        .{
            .binding_index = 4,
            .access_start = 16,
            .register = .sgpr_16,
            .dword_length = 4,
            .code_offset = 0xc,
            .flags = .{},
            .info = .{ .uniform_buffer = .{ .length = 0xc0 } },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, full_analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, full_analysis.access_chains);
}

test "analyze ps many rsrc references" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_psmanyref.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(34, analysis.num_sgprs);
    try testing.expectEqual(7, analysis.num_vgprs);
    try testing.expectEqual(0x1, analysis.mrt_bits);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // binding 0
        .{ .id = 0, .next = null, .instruction = .{ .offset = 48 } },
        .{ .id = 1, .next = 0, .instruction = .{ .dereference = {} } },
        .{ .id = 2, .next = 1, .instruction = .{ .offset = 8 } },
        // binding 1
        .{ .id = 3, .next = null, .instruction = .{ .offset = 16 } },
        // binding 2
        .{ .id = 4, .next = null, .instruction = .{ .offset = 48 } },
        // binding 3
        .{ .id = 5, .next = null, .instruction = .{ .offset = 0 } },
        .{ .id = 6, .next = 5, .instruction = .{ .dereference = {} } },
        .{ .id = 7, .next = 6, .instruction = .{ .offset = 8 } },
        // binding 4
        .{ .id = 8, .next = null, .instruction = .{ .offset = 32 } },
        .{ .id = 9, .next = 8, .instruction = .{ .dereference = {} } },
        .{ .id = 10, .next = 9, .instruction = .{ .offset = 8 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = 0,
            .access_start = 2,
            .register = .sgpr_28,
            .dword_length = 4,
            .code_offset = 0x18,
            .flags = .{},
            .info = .{ .uniform_buffer = .{ .length = 0x48 } },
        },
        .{
            .binding_index = 1,
            .access_start = 3,
            .register = .sgpr_4,
            .dword_length = 8,
            .code_offset = 0x28,
            .flags = .{},
            .info = .{ .image = {} },
        },
        .{
            .binding_index = 2,
            .access_start = 4,
            .register = .sgpr_12,
            .dword_length = 4,
            .code_offset = 0x28,
            .flags = .{},
            .info = .{ .sampler = {} },
        },
        .{
            .binding_index = 3,
            .access_start = 7,
            .register = .sgpr_16,
            .dword_length = 8,
            .code_offset = 0x30,
            .flags = .{},
            .info = .{ .image = {} },
        },
        .{
            .binding_index = 4,
            .access_start = 10,
            .register = .sgpr_24,
            .dword_length = 4,
            .code_offset = 0x30,
            .flags = .{},
            .info = .{ .sampler = {} },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze many samples" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_manysamples.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(16, analysis.num_sgprs);
    try testing.expectEqual(34, analysis.num_vgprs);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // binding 0
        .{ .id = 0, .next = null, .instruction = .{ .offset = 0 } },
        .{ .id = 1, .next = 0, .instruction = .{ .dereference = {} } },
        .{ .id = 2, .next = 1, .instruction = .{ .offset = 0 } },
        // binding 1
        .{ .id = 3, .next = null, .instruction = .{ .offset = 32 } },
        .{ .id = 4, .next = 3, .instruction = .{ .dereference = {} } },
        .{ .id = 5, .next = 4, .instruction = .{ .offset = 0 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = 0,
            .access_start = 2,
            .register = .sgpr_8,
            .dword_length = 8,
            .code_offset = 0xa0,
            .flags = .{},
            .info = .{ .image = {} },
        },
        .{
            .binding_index = 1,
            .access_start = 5,
            .register = .sgpr_4,
            .dword_length = 4,
            .code_offset = 0xa0,
            .flags = .{},
            .info = .{ .sampler = {} },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze compute RW" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_compute_rw.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(17, analysis.num_sgprs);
    try testing.expectEqual(2, analysis.num_vgprs);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // binding 0
        .{ .id = 0, .next = null, .instruction = .{ .offset = 48 } },
        // binding 1
        .{ .id = 1, .next = null, .instruction = .{ .offset = 16 } },
        // binding 2
        .{ .id = 2, .next = null, .instruction = .{ .offset = 32 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = 0,
            .access_start = 0,
            .register = .sgpr_12,
            .dword_length = 4,
            .code_offset = 0x8,
            .flags = .{},
            .info = .{ .uniform_buffer = .{ .length = 8 } },
        },
        .{
            .binding_index = 1,
            .access_start = 1,
            .register = .sgpr_4,
            .dword_length = 4,
            .code_offset = 0x20,
            .flags = .{},
            .info = .{ .storage_buffer = .{ .length = 4 } },
        },
        .{
            .binding_index = 2,
            .access_start = 2,
            .register = .sgpr_8,
            .dword_length = 4,
            .code_offset = 0x34,
            .flags = .{ .is_written = true },
            .info = .{ .storage_buffer = .{ .length = 4 } },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze constbuf mtbuf smrd" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_constbuf_mtbuf_smrd.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(32, analysis.num_sgprs);
    try testing.expectEqual(34, analysis.num_vgprs);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // binding 0
        .{ .id = 0, .next = null, .instruction = .{ .offset = 32 } },
        // binding 1
        .{ .id = 1, .next = null, .instruction = .{ .offset = 32 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = 0,
            .access_start = 0,
            .register = .sgpr_8,
            .dword_length = 4,
            .code_offset = 0x0,
            .flags = .{},
            .info = .{ .storage_buffer = .{ .length = 0x10 } },
        },
        .{
            .binding_index = 1,
            .access_start = 1,
            .register = .sgpr_8,
            .dword_length = 4,
            .code_offset = 0x30,
            .flags = .{},
            .info = .{ .uniform_buffer = .{ .length = 0x40 } },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze img load" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/asm_img_load.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    try testing.expectEqual(1, analysis.resources.len);
    try testing.expectEqual(12, analysis.num_sgprs);
    try testing.expectEqual(5, analysis.num_vgprs);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // binding 0
        .{ .id = 0, .next = null, .instruction = .{ .offset = 16 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = 0,
            .access_start = 0,
            .register = .sgpr_4,
            .dword_length = 8,
            .code_offset = 0x0,
            .flags = .{},
            .info = .{ .image = {} },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}

test "analyze vs shader copying indirect table s[7:8] to s[0:1]" {
    const alloc = testing.allocator;
    const gcn_code align(@alignOf(u32)) = @embedFile("data/cube_s78_s01.vert.gcn");

    var analysis = try gcn.Analyzer.scan(alloc, @ptrCast(@alignCast(gcn_code)), .{});
    defer analysis.deinit(alloc);

    const expected_chains = [_]gcn.Analyzer.AccessChain{
        // code pointer 0
        .{ .id = 0, .next = null, .instruction = .{ .dereference = {} } },
        // binding 0
        .{ .id = 1, .next = 0, .instruction = .{ .offset = 0 } },
        .{ .id = 2, .next = null, .instruction = .{ .offset = 0 } },
        .{ .id = 3, .next = 2, .instruction = .{ .dereference = {} } },
        .{ .id = 4, .next = 3, .instruction = .{ .offset = 28 } },
    };
    const expected_resources = [_]gcn.Analyzer.Resource{
        .{
            .binding_index = null,
            .access_start = 1,
            .register = .sgpr_0,
            .dword_length = 2,
            .code_offset = 0x0,
            .flags = .{},
            .info = .{ .code = {} },
        },
        .{
            .binding_index = 0,
            .access_start = 4,
            .register = .sgpr_0,
            .dword_length = 4,
            .code_offset = 0x14,
            .flags = .{},
            .info = .{ .uniform_buffer = .{ .length = 0x40 } },
        },
    };

    try testing.expectEqualSlices(gcn.Analyzer.Resource, &expected_resources, analysis.resources);
    try testing.expectEqualSlices(gcn.Analyzer.AccessChain, &expected_chains, analysis.access_chains);
}
