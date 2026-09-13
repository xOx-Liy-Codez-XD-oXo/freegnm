const std = @import("std");
const Io = std.Io;
const math = std.math;
const mem = std.mem;

const psb = @import("../psb.zig");
const gnm = @import("../gnm.zig");

sb_header: psb.BinaryHeader,
file_header: gnm.ShaderFileHeader,
constant_buffer_length: u20,
scratch_size: u16,

stage: Stage,
gpu_mode: ?gnm.GpuMode,
gcn_code: []const u32,

resource_slots: []const gnm.InputUsageSlot,
inputs: Inputs,
outputs: Outputs,

pub const Stage = union(gnm.ShaderFileHeader.Type) {
    // TODO: reverse missing shader types below
    vertex: gnm.VsShader,
    pixel: gnm.PsShader,
    geometry: void,
    compute: gnm.CsShader,
    @"export": void,
    local: void,
    hull: void,
};

pub const Inputs = union(gnm.ShaderFileHeader.Type) {
    vertex: []const gnm.VertexInputSemantic,
    pixel: []const gnm.PixelInputSemantic,
    geometry: void,
    compute: []const gnm.VertexInputSemantic,
    @"export",
    local,
    hull: void,

    pub fn length(self: Inputs) usize {
        return switch (self) {
            .vertex => |i| i.len,
            .pixel => |i| i.len,
            .compute => |i| i.len,
            else => @panic("TODO"),
        };
    }
};

pub const Outputs = union(gnm.ShaderFileHeader.Type) {
    vertex: []const gnm.VertexExportSemantic,
    pixel,
    geometry,
    compute,
    @"export",
    local,
    hull: void,

    pub fn length(self: Outputs) usize {
        return switch (self) {
            .vertex => |i| i.len,
            .pixel => 0,
            else => @panic("TODO"),
        };
    }
};

const Shader = @This();

pub const LoadError = error{
    InvalidMagic,
    InvalidShaderLength,
    InvalidShaderAlignment,
    ProgramAlreadyPatched,
} || Io.Reader.Error || mem.Allocator.Error;

pub fn load(arena: mem.Allocator, reader: *Io.Reader) LoadError!Shader {
    // skip the PSB wrapper's header and go into the GNM shader data
    // TODO: do we want any of its data?
    const bh = try reader.takeStruct(psb.BinaryHeader, .little);

    // read generic shader header
    const fh = try reader.takeStruct(gnm.ShaderFileHeader, .little);
    if (fh.magic != gnm.ShaderFileHeader.MAGIC) {
        @branchHint(.unlikely);
        return error.InvalidMagic;
    }

    // HACK: takeStruct can't handle ShaderCommonData's shader_len's 23 bits,
    // so workaround it
    const scd: gnm.ShaderCommonData = @bitCast(try reader.takeInt(u64, .little));

    if (scd.shader_len <= @sizeOf(gnm.ShaderBinaryInfo)) {
        @branchHint(.unlikely);
        return error.InvalidShaderLength;
    }
    if (scd.shader_len & 0x3 != 0) {
        @branchHint(.unlikely);
        return error.InvalidShaderAlignment;
    }

    var cur_offset: usize = @sizeOf(psb.BinaryHeader) +
        @sizeOf(gnm.ShaderFileHeader) +
        @sizeOf(gnm.ShaderCommonData);

    const stage: Stage = st: {
        switch (fh.type) {
            .vertex => {
                const vsh = try reader.takeStruct(gnm.VsShader, .little);
                if ((vsh.registers.spi_shader_pgm_lo_vs & 0x3) != 0) {
                    @branchHint(.unlikely);
                    return error.InvalidShaderAlignment;
                }
                if (vsh.registers.spi_shader_pgm_hi_vs != 0xffffffff) {
                    @branchHint(.unlikely);
                    return error.ProgramAlreadyPatched;
                }
                cur_offset += @sizeOf(gnm.VsShader);
                break :st .{ .vertex = vsh };
            },
            .pixel => {
                const psh = try reader.takeStruct(gnm.PsShader, .little);
                if ((psh.registers.spi_shader_pgm_lo_ps & 0x3) != 0) {
                    @branchHint(.unlikely);
                    return error.InvalidShaderAlignment;
                }
                if (psh.registers.spi_shader_pgm_hi_ps != 0xffffffff) {
                    @branchHint(.unlikely);
                    return error.ProgramAlreadyPatched;
                }
                cur_offset += @sizeOf(gnm.PsShader);
                break :st .{ .pixel = psh };
            },
            .geometry => break :st .{ .geometry = {} },
            .compute => {
                const csh = try reader.takeStruct(gnm.CsShader, .little);
                if ((csh.registers.compute_pgm_lo & 0x3) != 0) {
                    @branchHint(.unlikely);
                    return error.InvalidShaderAlignment;
                }
                if (csh.registers.compute_pgm_hi != 0xffffffff) {
                    @branchHint(.unlikely);
                    return error.ProgramAlreadyPatched;
                }
                cur_offset += @sizeOf(gnm.CsShader);
                break :st .{ .compute = csh };
            },
            .@"export" => break :st .{ .@"export" = {} },
            .local => break :st .{ .local = {} },
            .hull => break :st .{ .hull = {} },
        }
    };

    const resource_slots = try arena.alloc(gnm.InputUsageSlot, scd.num_input_usage_slots);
    for (resource_slots) |*out_slot| {
        out_slot.* = try reader.takeStruct(gnm.InputUsageSlot, .little);
    }
    cur_offset += @sizeOf(gnm.InputUsageSlot) * scd.num_input_usage_slots;

    const inputs: Inputs, const outputs: Outputs = io: {
        switch (stage) {
            else => @panic("TODO"),
            .vertex => |vs| {
                const inputs = try arena.alloc(gnm.VertexInputSemantic, vs.num_input_semantics);
                for (inputs) |*entry| {
                    entry.* = try reader.takeStruct(gnm.VertexInputSemantic, .little);
                }
                cur_offset += @sizeOf(gnm.VertexInputSemantic) * vs.num_input_semantics;

                const outputs = try arena.alloc(gnm.VertexExportSemantic, vs.num_export_semantics);
                for (outputs) |*entry| {
                    entry.* = @fromBackingInt(try reader.takeInt(u16, .little));
                }
                cur_offset += @sizeOf(gnm.VertexExportSemantic) * vs.num_export_semantics;

                break :io .{ .{ .vertex = inputs }, .{ .vertex = outputs } };
            },
            .compute => |cs| {
                var inputs: []gnm.VertexInputSemantic = &.{};
                if (cs.version > 0) {
                    inputs = try arena.alloc(gnm.VertexInputSemantic, cs.per_version.new.num_input_semantics);
                    for (inputs) |*entry| {
                        entry.* = try reader.takeStruct(gnm.VertexInputSemantic, .little);
                    }
                    cur_offset += @sizeOf(gnm.VertexInputSemantic) * cs.per_version.new.num_input_semantics;
                }

                break :io .{ .{ .compute = inputs }, .{ .compute = {} } };
            },
            .pixel => |ps| {
                const inputs = try arena.alloc(gnm.PixelInputSemantic, ps.num_input_semantics);
                for (inputs) |*entry| {
                    entry.* = @fromBackingInt(try reader.takeInt(u16, .little));
                }
                cur_offset += @sizeOf(gnm.PixelInputSemantic) * ps.num_input_semantics;

                break :io .{ .{ .pixel = inputs }, .{ .pixel = {} } };
            },
        }
    };

    const remain_aligned_bytes = mem.alignForward(usize, cur_offset, 4) - cur_offset;
    if (remain_aligned_bytes > 0) {
        try reader.discardAll(remain_aligned_bytes);
    }

    const num_gcn_dwords = (scd.shader_len - @sizeOf(gnm.ShaderBinaryInfo)) / @sizeOf(u32);
    const gcn_code = try arena.alloc(u32, num_gcn_dwords);
    try reader.readSliceAll(@ptrCast(gcn_code));

    const gpu_mode: ?gnm.GpuMode =
        if (fh.target_gpu_modes.base and !fh.target_gpu_modes.neo)
            .base
        else if (!fh.target_gpu_modes.base and fh.target_gpu_modes.neo)
            .neo
        else
            null;

    return .{
        .sb_header = bh,
        .file_header = fh,
        .constant_buffer_length = scd.constant_buffer_len_dqwords * 16,
        .scratch_size = scd.scratch_size,
        .stage = stage,
        .gpu_mode = gpu_mode,
        .gcn_code = gcn_code,
        .resource_slots = resource_slots,
        .inputs = inputs,
        .outputs = outputs,
    };
}

pub fn upload(self: *Shader, gpu_alloc: mem.Allocator) mem.Allocator.Error!void {
    // upload GCN bytecode
    const code_gpu = try gpu_alloc.alignedAlloc(
        u32,
        .fromByteUnits(gnm.ALIGNMENT_SHADER_BYTES),
        self.gcn_code.len,
    );
    errdefer gpu_alloc.free(code_gpu);
    @memcpy(code_gpu, self.gcn_code);

    // patch shader descriptor to hold the GPU code address
    const gpu_ptr = math.cast(u56, @intFromPtr(code_gpu.ptr)) orelse unreachable;
    switch (self.stage) {
        else => @panic("TODO: add missing shader stages"),
        .vertex => |*vs| vs.registers.patchAddress(gpu_ptr),
        .pixel => |*ps| ps.registers.patchAddress(gpu_ptr),
        .compute => |*cs| cs.registers.patchAddress(gpu_ptr),
    }
}

pub const Reflection = struct {
    binary_info: gnm.ShaderBinaryInfo,

    buffers: []const psb.Buffer,
    constants: []const psb.Constant,
    elements: []const psb.Element,
    samplers: []const psb.SamplerState,
    inputs: []const psb.Attribute,
    outputs: []const psb.Attribute,
    stream_outs: []const psb.StreamOut,

    value_table: [:0]const u8,
    string_table: [:0]const u8,
};

pub const ParseReflectionError = error{
    InvalidShaderBinary,
    StageMismatch,
} || Io.Reader.Error || mem.Allocator.Error;

pub fn parseReflection(
    self: Shader,
    arena: mem.Allocator,
    reader: *Io.Reader,
) !Reflection {
    const sbi = try reader.takeStruct(gnm.ShaderBinaryInfo, .little);
    if (!mem.eql(u8, &sbi.magic, &gnm.ShaderBinaryInfo.MAGIC))
        return error.InvalidShaderBinary;

    switch (sbi.info.type) {
        .ps => if (self.stage != .pixel) {
            @branchHint(.unlikely);
            return error.StageMismatch;
        },
        .vs_vs, .vs_es, .vs_ls => if (self.stage != .vertex) {
            @branchHint(.unlikely);
            return error.StageMismatch;
        },
        .cs => if (self.stage != .compute) {
            @branchHint(.unlikely);
            return error.StageMismatch;
        },
        .gs, .gs_vs => if (self.stage != .geometry) {
            @branchHint(.unlikely);
            return error.StageMismatch;
        },
        .hs => if (self.stage != .hull) {
            @branchHint(.unlikely);
            return error.StageMismatch;
        },
        .ds_vs, .ds_es => @panic("TODO"),
    }

    const param_info = try reader.takeStruct(psb.ParamInfo, .little);

    const buffers = try arena.alloc(psb.Buffer, param_info.num_buffer_resources);
    const constants = try arena.alloc(psb.Constant, param_info.num_constants);
    const elements = try arena.alloc(psb.Element, param_info.num_variables);
    const samplers = try arena.alloc(psb.SamplerState, param_info.num_sampler_resources);
    const inputs = try arena.alloc(psb.Attribute, param_info.num_input_attributes);
    const outputs = try arena.alloc(psb.Attribute, param_info.num_output_attributes);
    const stream_outs = try arena.alloc(psb.StreamOut, param_info.num_stream_outs);
    const value_table = try arena.allocSentinel(u8, param_info.value_table_byte_len, 0);
    const string_table = try arena.allocSentinel(u8, param_info.string_table_byte_len, 0);

    for (buffers) |*b| {
        b.* = try reader.takeStruct(psb.Buffer, .little);
    }
    for (constants) |*c| {
        c.* = try reader.takeStruct(psb.Constant, .little);
    }
    for (elements) |*e| {
        e.* = try reader.takeStruct(psb.Element, .little);
    }
    for (samplers) |*s| {
        s.* = try reader.takeStruct(psb.SamplerState, .little);
    }
    for (inputs) |*i| {
        i.* = try reader.takeStruct(psb.Attribute, .little);
    }
    for (outputs) |*o| {
        o.* = try reader.takeStruct(psb.Attribute, .little);
    }
    for (stream_outs) |*so| {
        so.* = try reader.takeStruct(psb.StreamOut, .little);
    }

    try reader.readSliceAll(value_table);
    try reader.readSliceAll(string_table);

    return .{
        .binary_info = sbi,
        .buffers = buffers,
        .constants = constants,
        .elements = elements,
        .samplers = samplers,
        .inputs = inputs,
        .outputs = outputs,
        .stream_outs = stream_outs,
        .value_table = value_table,
        .string_table = string_table,
    };
}

const testing = std.testing;

test "parsing vertex shader" {
    const vert_sb = @embedFile("data/gltf.vert.sb");

    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    var data_reader = Io.Reader.fixed(vert_sb);
    var sh = try Shader.load(arena, &data_reader);

    try testing.expectEqual(0, sh.sb_header.version.major);
    try testing.expectEqual(4, sh.sb_header.version.minor);
    try testing.expectEqual(0, sh.sb_header.version.compiler);
    try testing.expectEqual(.{ 0, 0 }, sh.sb_header.association_hash);
    try testing.expectEqual(.vertex, sh.sb_header.type);
    try testing.expectEqual(.isa, sh.sb_header.source_code_type);
    try testing.expectEqual(.unspecified, sh.sb_header.compiler.type);
    try testing.expectEqual(0x2d8, sh.sb_header.code_byte_length);
    try testing.expectEqual(.vertex, sh.sb_header.variant.vs);

    try testing.expectEqualDeep(gnm.ShaderFileHeader{
        .version_major = 7,
        .version_minor = 2,
        .type = .vertex,
        .shader_header_len_dwords = 19,
        .has_shader_aux_data = 0,
        .target_gpu_modes = .{
            .base = true,
        },
    }, sh.file_header);

    try testing.expectEqual(3, sh.resource_slots.len);
    try testing.expectEqual(0, sh.constant_buffer_length);
    try testing.expectEqual(0, sh.scratch_size);

    try testing.expect(sh.stage == .vertex);
    try testing.expectEqualDeep(gnm.VsShader{
        .registers = .{
            .spi_shader_pgm_lo_vs = 0x4c,
            .spi_shader_pgm_hi_vs = 0xffffffff,
            .spi_shader_pgm_rsrc1_vs = .{
                .vgprs = 6,
                .sgprs = 5,
                .priority = 0,
                .float_mode = .fp_16_64_denorms,
                .priv = false,
                .dx10_clamp = true,
                .debug_mode = false,
                .ieee_mode = false,
                .vgpr_comp_cnt = 1,
                .cu_group_enable = false,
                .cache_ctl = 0,
                .cdbg_user = false,
            },
            .spi_shader_pgm_rsrc2_vs = .{
                .scratch_en = false,
                .user_sgpr = 11,
                .trap_present = false,
                .oc_lds_en = false,
                .so_base0_en = false,
                .so_base1_en = false,
                .so_base2_en = false,
                .so_base3_en = false,
                .so_en = false,
                .excp_en = .{},
                .dispatch_draw_en = false,
            },
            .spi_vs_out_config = .{
                .vs_export_count = 3,
                .vs_half_pack = false,
            },
            .spi_shader_pos_format = .{
                .pos0_export_format = .@"4comp",
            },
            .pa_cl_vs_out_cntl = .{},
        },
        .num_input_semantics = 4,
        .num_export_semantics = 4,
        .gs_mode_or_num_input_semantics_cs = 0,
        .fetch_control = 0,
    }, sh.stage.vertex);

    try testing.expectEqual(3, sh.resource_slots.len);
    {
        const slot = sh.resource_slots[0];
        try testing.expectEqual(.sub_ptr_fetch_shader, slot.usage_type);
        try testing.expectEqual(0, slot.api_slot);
        try testing.expectEqual(0, slot.start_register);
        try testing.expectEqual(false, slot.register_info.default.using_large_resource);
        try testing.expectEqual(
            gnm.InputUsageSlot.ResourceType.buffer_or_pointer,
            slot.register_info.default.resource_type,
        );
        try testing.expectEqual(0, slot.register_info.default.chunk_mask);
    }
    {
        const slot = sh.resource_slots[1];
        try testing.expectEqual(.ptr_vertex_buffer_table, slot.usage_type);
        try testing.expectEqual(0, slot.api_slot);
        try testing.expectEqual(2, slot.start_register);
        try testing.expectEqual(false, slot.register_info.default.using_large_resource);
        try testing.expectEqual(.buffer_or_pointer, slot.register_info.default.resource_type);
        try testing.expectEqual(0, slot.register_info.default.chunk_mask);
    }
    {
        const slot = sh.resource_slots[2];
        try testing.expectEqual(.ptr_indirect_resource_table, slot.usage_type);
        try testing.expectEqual(0, slot.api_slot);
        try testing.expectEqual(7, slot.start_register);
        try testing.expectEqual(false, slot.register_info.default.using_large_resource);
        try testing.expectEqual(.buffer_or_pointer, slot.register_info.default.resource_type);
        try testing.expectEqual(0, slot.register_info.default.chunk_mask);
    }

    try testing.expectEqual(4, sh.inputs.len);
    try testing.expectEqualDeep(gnm.VertexInputSemantic{
        .semantic = 0,
        .vgpr = 4,
        .size_in_elements = 4,
    }, sh.inputs[0].vertex);
    try testing.expectEqualDeep(gnm.VertexInputSemantic{
        .semantic = 1,
        .vgpr = 8,
        .size_in_elements = 4,
    }, sh.inputs[1].vertex);
    try testing.expectEqualDeep(gnm.VertexInputSemantic{
        .semantic = 2,
        .vgpr = 12,
        .size_in_elements = 4,
    }, sh.inputs[2].vertex);
    try testing.expectEqualDeep(gnm.VertexInputSemantic{
        .semantic = 3,
        .vgpr = 16,
        .size_in_elements = 4,
    }, sh.inputs[3].vertex);

    try testing.expectEqual(4, sh.outputs.len);
    try testing.expectEqualDeep(gnm.VertexExportSemantic{
        .semantic = 15,
        .out_index = 0,
        .type = .{},
    }, sh.outputs[0].vertex);
    try testing.expectEqualDeep(gnm.VertexExportSemantic{
        .semantic = 16,
        .out_index = 1,
        .type = .{},
    }, sh.outputs[1].vertex);
    try testing.expectEqualDeep(gnm.VertexExportSemantic{
        .semantic = 17,
        .out_index = 2,
        .type = .{},
    }, sh.outputs[2].vertex);
    try testing.expectEqualDeep(gnm.VertexExportSemantic{
        .semantic = 18,
        .out_index = 3,
        .type = .{},
    }, sh.outputs[3].vertex);

    const gcn_code = sh.gcn_code;
    const gcn_hash = std.hash.Wyhash.hash(0, @ptrCast(gcn_code));
    try testing.expectEqual(0x7f482d8419e767dd, gcn_hash);

    const ref = try sh.parseReflection(arena, &data_reader);

    try testing.expectEqualDeep(gnm.ShaderBinaryInfo{
        .info = .{
            .is_pssl_or_cg = true,
            .is_source_cached = false,
            .type = .vs_vs,
            .length = 0x260,
        },
        .chunk_usage_base_offset_dwords = 0,
        .num_input_usage_slots = 0,
        .srt = .{
            .has_shader_resource_tables = false,
            .is_srt_used_info_valid = false,
            .has_extended_usage_info = false,
            .source_hash_type = 0,
        },
        .footer_version = 0,
        .association_hash = [2]u32{ 0, 0 },
        .crc32 = 0x759a22ef,
    }, ref.binary_info);

    try testing.expectEqual(0, ref.buffers.len);
    try testing.expectEqual(0, ref.constants.len);
    try testing.expectEqual(0, ref.elements.len);
    try testing.expectEqual(0, ref.samplers.len);
    try testing.expectEqual(0, ref.inputs.len);
    try testing.expectEqual(0, ref.outputs.len);
    try testing.expectEqual(0, ref.stream_outs.len);
    try testing.expectEqual(0, ref.value_table.len);
    try testing.expectEqual(0, ref.string_table.len);

    try sh.upload(arena);
}

test "parsing vertex shader with uneven vertex exports" {
    const vert_sb = @embedFile("data/cube.vert.sb");

    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    var data_reader = Io.Reader.fixed(vert_sb);
    const sh = try psb.Shader.load(arena, &data_reader);
    _ = try sh.parseReflection(arena, &data_reader);
}

test "parsing pixel shader" {
    const frag_sb = @embedFile("data/gltf.frag.sb");

    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();
    var data_reader = Io.Reader.fixed(frag_sb);

    var sh = try psb.Shader.load(arena, &data_reader);

    try testing.expectEqual(0, sh.sb_header.version.major);
    try testing.expectEqual(4, sh.sb_header.version.minor);
    try testing.expectEqual(0, sh.sb_header.version.compiler);
    try testing.expectEqual(.{ 0, 0 }, sh.sb_header.association_hash);
    try testing.expectEqual(.fragment, sh.sb_header.type);
    try testing.expectEqual(.isa, sh.sb_header.source_code_type);
    try testing.expectEqual(.unspecified, sh.sb_header.compiler.type);
    try testing.expectEqual(0x578, sh.sb_header.code_byte_length);

    try testing.expectEqualDeep(gnm.ShaderFileHeader{
        .version_major = 7,
        .version_minor = 2,
        .type = .pixel,
        .shader_header_len_dwords = 18,
        .has_shader_aux_data = 0,
        .target_gpu_modes = .{
            .base = true,
        },
    }, sh.file_header);

    try testing.expectEqual(1, sh.resource_slots.len);
    try testing.expectEqual(0, sh.constant_buffer_length);
    try testing.expectEqual(0, sh.scratch_size);

    try testing.expect(sh.stage == .pixel);
    try testing.expectEqualDeep(gnm.PsShader{
        .registers = .{
            .spi_shader_pgm_lo_ps = 0x48,
            .spi_shader_pgm_hi_ps = 0xffffffff,
            .spi_shader_pgm_rsrc1_ps = .{
                .vgprs = 7,
                .sgprs = 2,
                .priority = 0,
                .float_mode = .fp_16_64_denorms,
                .priv = false,
                .dx10_clamp = true,
                .debug_mode = false,
                .ieee_mode = false,
                .cu_group_disable = false,
                .cache_ctl = 0,
                .cdbg_user = false,
            },
            .spi_shader_pgm_rsrc2_ps = .{
                .scratch_en = false,
                .user_sgpr = 4,
                .trap_present = false,
                .wave_cnt_en = false,
                .extra_lds_size = 0,
                .excp_en = .{},
            },
            .spi_shader_z_format = .{
                .z_export_format = .zero,
            },
            .spi_shader_col_format = .{
                .col0_export_format = .fp16_abgr,
            },
            .spi_ps_input_ena = .{
                .persp_center_ena = true,
            },
            .spi_ps_input_addr = .{
                .offset = 2,
                .default_val = .@"0_0_0_0",
                .flat_shade = false,
                .cyl_wrap = 0,
                .pt_sprite_tex = false,
                .dup = false,
                .fp16_interp_mode = false,
                .use_default_attr1 = false,
                .default_val_attr1 = .@"0_0_0_0",
                .pt_sprite_tex_attr1 = false,
                .attr0_valid = false,
                .attr1_valid = false,
            },
            .spi_ps_in_control = .{
                .num_interp = 4,
                .param_gen = false,
                .bc_optimize_disable = false,
            },
            .spi_baryc_cntl = .{
                .persp_center_cntl = false,
                .persp_centroid_cntl = false,
                .linear_center_cntl = false,
                .linear_centroid_cntl = false,
                .pos_float_location = 0,
                .pos_float_ulc = false,
                .front_face_all_bits = true,
            },
            .db_shader_control = .{
                .z_export_enable = false,
                .stencil_test_val_export_enable = false,
                .stencil_op_val_export_enable = false,
                .z_order = .early_z_then_late_z,
                .kill_enable = false,
                .coverage_to_mask_enable = false,
                .mask_export_enable = false,
                .exec_on_hier_fail = false,
                .exec_on_noop = false,
                .alpha_to_mask_disable = false,
                .depth_before_shader = false,
                .conservative_z_export = .export_any_z,
            },
            .cb_shader_mask = .{ .target0_enable = .on },
        },
        .num_input_semantics = 4,
    }, sh.stage.pixel);

    try testing.expectEqual(1, sh.resource_slots.len);
    {
        const slot = sh.resource_slots[0];
        try testing.expectEqual(.ptr_indirect_resource_table, slot.usage_type);
        try testing.expectEqual(0, slot.api_slot);
        try testing.expectEqual(0, slot.start_register);
        try testing.expectEqual(false, slot.register_info.default.using_large_resource);
        try testing.expectEqual(.buffer_or_pointer, slot.register_info.default.resource_type);
        try testing.expectEqual(0, slot.register_info.default.chunk_mask);
    }

    try testing.expectEqual(4, sh.inputs.len);
    {
        const input = sh.inputs[0].pixel;
        try testing.expectEqual(15, input.semantic);
        try testing.expectEqual(.@"0_0_0_0", input.default_value);
        try testing.expectEqual(false, input.flat_shade);
        try testing.expectEqual(false, input.sel_linear);
        try testing.expectEqual(false, input.hw.base.custom);
    }
    {
        const input = sh.inputs[1].pixel;
        try testing.expectEqual(16, input.semantic);
        try testing.expectEqual(.@"0_0_0_0", input.default_value);
        try testing.expectEqual(false, input.flat_shade);
        try testing.expectEqual(false, input.sel_linear);
        try testing.expectEqual(false, input.hw.base.custom);
    }
    {
        const input = sh.inputs[2].pixel;
        try testing.expectEqual(17, input.semantic);
        try testing.expectEqual(.@"0_0_0_0", input.default_value);
        try testing.expectEqual(false, input.flat_shade);
        try testing.expectEqual(false, input.sel_linear);
        try testing.expectEqual(false, input.hw.base.custom);
    }
    {
        const input = sh.inputs[3].pixel;
        try testing.expectEqual(18, input.semantic);
        try testing.expectEqual(.@"0_0_0_0", input.default_value);
        try testing.expectEqual(false, input.flat_shade);
        try testing.expectEqual(false, input.sel_linear);
        try testing.expectEqual(false, input.hw.base.custom);
    }

    const gcn_code = sh.gcn_code;
    const gcn_hash = std.hash.Wyhash.hash(0, @ptrCast(gcn_code));
    try testing.expectEqual(0x80c67515970c1360, gcn_hash);

    const ref = try sh.parseReflection(arena, &data_reader);

    try testing.expectEqualDeep(gnm.ShaderBinaryInfo{
        .info = .{
            .is_pssl_or_cg = true,
            .is_source_cached = false,
            .type = .ps,
            .length = 0x504,
        },
        .chunk_usage_base_offset_dwords = 0,
        .num_input_usage_slots = 0,
        .srt = .{
            .has_shader_resource_tables = false,
            .is_srt_used_info_valid = false,
            .has_extended_usage_info = false,
            .source_hash_type = 0,
        },
        .footer_version = 0,
        .association_hash = [2]u32{ 0, 0 },
        .crc32 = 0x68392710,
    }, ref.binary_info);

    try testing.expectEqual(0, ref.buffers.len);
    try testing.expectEqual(0, ref.constants.len);
    try testing.expectEqual(0, ref.elements.len);
    try testing.expectEqual(0, ref.samplers.len);
    try testing.expectEqual(0, ref.inputs.len);
    try testing.expectEqual(0, ref.outputs.len);
    try testing.expectEqual(0, ref.stream_outs.len);
    try testing.expectEqual(0, ref.value_table.len);
    try testing.expectEqual(0, ref.string_table.len);

    try sh.upload(arena);
}
