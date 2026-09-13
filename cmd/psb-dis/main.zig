const std = @import("std");
const Io = std.Io;
const fatal = std.process.fatal;

const gnm = @import("gnm");
const gcn = gnm.gcn;
const psb = gnm.psb;

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
        fatal("Please pass an input path to a PSB shader file", .{});
    const file = Io.Dir.cwd().openFile(io, file_path, .{}) catch |err| {
        fatal("Failed to open file {s} with {}", .{ file_path, err });
    };
    defer file.close(io);

    var file_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &file_buf);

    const sh = psb.Shader.load(arena, &file_reader.interface) catch |err| {
        fatal("Failed to parse shader with {t}!", .{err});
    };

    const sb = sh.sb_header;
    try stdout.print(
        \\Shader Binary header:
        \\ | Version: {}.{} (compiler version: {})
        \\ | Association hash: {x} {x}
        \\ | Shader type: {t}
        \\ | Source code type: {t}
        \\ | Has Shader Resource Table (SRT): {}
        \\ | Compiler type: {t}
        \\ | Code byte length: 0x{x}
        \\
    , .{
        sb.version.major,
        sb.version.minor,
        sb.version.compiler,
        sb.association_hash[0],
        sb.association_hash[1],
        sb.type,
        sb.source_code_type,
        sb.uses_shader_resource_table,
        sb.compiler.type,
        sb.code_byte_length,
    });
    switch (sb.type) {
        .vertex => try stdout.print(" | Vertex variant: {t}\n", .{sb.variant.vs}),
        .geometry => try stdout.print(" | Geometry variant: {t}\n", .{sb.variant.gs}),
        .hull => try stdout.print(" | Hull variant: {t}\n", .{sb.variant.hs}),
        .domain => try stdout.print(" | Domain variant: {t}\n", .{sb.variant.ds}),
        else => {},
    }

    const fh = sh.file_header;
    try stdout.print(
        \\  GNM shader file header:
        \\   | Magic: 0x{x}
        \\   | Version: {}.{}
        \\   | Shader type: {t}
        \\   | Shader header size in DWORDs: {} 
        \\   | Has shader auxiliary data: {s}
        \\   | Target GPU mode: {s}
        \\
    , .{
        fh.magic,
        fh.version_major,
        fh.version_minor,
        fh.type,
        fh.shader_header_len_dwords,
        if (fh.has_shader_aux_data != 0) "true" else "false",
        if (fh.target_gpu_modes.base and fh.target_gpu_modes.neo)
            "Base + NEO"
        else if (fh.target_gpu_modes.base)
            "Base"
        else if (fh.target_gpu_modes.neo)
            "NEO"
        else
            "Unspecified",
    });

    try stdout.print(
        \\  GNM shader common data:
        \\   | Shader byte length: 0x{x}
        \\   | Number of input usage slots: {} 
        \\   | Constant Buffer's length in double QWORDs: {}
        \\   | Scratch size: {}
        \\
    , .{
        sh.gcn_code.len,
        sh.inputs.length(),
        sh.constant_buffer_length,
        sh.scratch_size,
    });

    switch (sh.stage) {
        .vertex => |vsh| {
            try stdout.print(
                \\  GNM Vertex Shader:
                \\   | Number of input semantics: {}
                \\   | Number of output/export semantics: {} 
                \\   | GS mode: {}
                \\   | Fetch control: {}
                \\
            , .{
                vsh.num_input_semantics,
                vsh.num_export_semantics,
                vsh.gs_mode_or_num_input_semantics_cs,
                vsh.fetch_control,
            });

            const regs = vsh.registers;
            try stdout.print(
                \\  GNM Vertex Shader registers:
                \\   | SPI Shader Program Low: 0x{x}
                \\   | SPI Shader Program High: 0x{x}
                \\   | SPI Shader Resource 1 (0x{x}):
                \\   | - VGPRs: {}
                \\   | - SGPRs: {}
                \\   | - Priority: {}
                \\   | - Float mode: {t}
                \\   | - Priv: {}
                \\   | - DX10 clamp: {}
                \\   | - Debug mode: {}
                \\   | - IEEE mode: {}
                \\   | - VGPR comp count: {}
                \\   | - CU group enable: {}
                \\   | - Cache control: {}
                \\   | - CDBG user: {}
                \\
            , .{
                regs.spi_shader_pgm_lo_vs,
                regs.spi_shader_pgm_hi_vs,

                @as(u32, @bitCast(regs.spi_shader_pgm_rsrc1_vs)),
                regs.spi_shader_pgm_rsrc1_vs.vgprs,
                regs.spi_shader_pgm_rsrc1_vs.sgprs,
                regs.spi_shader_pgm_rsrc1_vs.priority,
                regs.spi_shader_pgm_rsrc1_vs.float_mode,
                regs.spi_shader_pgm_rsrc1_vs.priv,
                regs.spi_shader_pgm_rsrc1_vs.dx10_clamp,
                regs.spi_shader_pgm_rsrc1_vs.debug_mode,
                regs.spi_shader_pgm_rsrc1_vs.ieee_mode,
                regs.spi_shader_pgm_rsrc1_vs.vgpr_comp_cnt,
                regs.spi_shader_pgm_rsrc1_vs.cu_group_enable,
                regs.spi_shader_pgm_rsrc1_vs.cache_ctl,
                regs.spi_shader_pgm_rsrc1_vs.cdbg_user,
            });
            try stdout.print(
                \\   | SPI Shader Resource 2 (0x{x}):
                \\   | - Scratch enabled: {}
                \\   | - User SGPR: {}
                \\   | - Trap present: {}
                \\   | - OC LDS enabled: {}
                \\   | - SO Base 0 enabled: {}
                \\   | - SO Base 1 enabled: {}
                \\   | - SO Base 2 enabled: {}
                \\   | - SO Base 3 enabled: {}
                \\   | - SO enabled: {}
                \\   | - Exception enabled: 0x{x}
                \\   |   * Invalid: {}
                \\   |   * Input denormal: {}
                \\   |   * Divide by Zero: {}
                \\   |   * Overflow: {}
                \\   |   * Underflow: {}
                \\   |   * Inexact: {}
                \\   |   * Int divide by zero: {}
                \\   |   * Address watch: {}
                \\   |   * Memory violation: {}
                \\   | - Dispatch draw enabled: {}
                \\
            , .{
                @as(u32, @bitCast(regs.spi_shader_pgm_rsrc2_vs)),
                regs.spi_shader_pgm_rsrc2_vs.scratch_en,
                regs.spi_shader_pgm_rsrc2_vs.user_sgpr,
                regs.spi_shader_pgm_rsrc2_vs.trap_present,
                regs.spi_shader_pgm_rsrc2_vs.oc_lds_en,
                regs.spi_shader_pgm_rsrc2_vs.so_base0_en,
                regs.spi_shader_pgm_rsrc2_vs.so_base1_en,
                regs.spi_shader_pgm_rsrc2_vs.so_base2_en,
                regs.spi_shader_pgm_rsrc2_vs.so_base3_en,
                regs.spi_shader_pgm_rsrc2_vs.so_en,
                @as(u9, @bitCast(regs.spi_shader_pgm_rsrc2_vs.excp_en)),
                regs.spi_shader_pgm_rsrc2_vs.excp_en.invalid,
                regs.spi_shader_pgm_rsrc2_vs.excp_en.input_denormal,
                regs.spi_shader_pgm_rsrc2_vs.excp_en.divide_by_zero,
                regs.spi_shader_pgm_rsrc2_vs.excp_en.overflow,
                regs.spi_shader_pgm_rsrc2_vs.excp_en.underflow,
                regs.spi_shader_pgm_rsrc2_vs.excp_en.inexact,
                regs.spi_shader_pgm_rsrc2_vs.excp_en.int_divide_by_zero,
                regs.spi_shader_pgm_rsrc2_vs.excp_en.address_watch,
                regs.spi_shader_pgm_rsrc2_vs.excp_en.memory_violation,
                regs.spi_shader_pgm_rsrc2_vs.dispatch_draw_en,
            });
            try stdout.print(
                \\   | SPI VS Out Config (0x{x}):
                \\   | - VS export count: {}
                \\   | - VS half pack: {}
                \\   | SPI Shader Pos Format (0x{x}):
                \\   | - Pos 0 export format: {t}
                \\   | - Pos 1 export format: {t}
                \\   | - Pos 2 export format: {t}
                \\   | - Pos 3 export format: {t}
                \\
            , .{
                @as(u32, @bitCast(regs.spi_vs_out_config)),
                regs.spi_vs_out_config.vs_export_count,
                regs.spi_vs_out_config.vs_half_pack,
                @as(u32, @bitCast(regs.spi_shader_pos_format)),
                regs.spi_shader_pos_format.pos0_export_format,
                regs.spi_shader_pos_format.pos1_export_format,
                regs.spi_shader_pos_format.pos2_export_format,
                regs.spi_shader_pos_format.pos3_export_format,
            });
            try stdout.print(
                \\   | PA CL VS Out Control (0x{x}):
                \\   | - Clip Distance enabled 0: {}
                \\   | - Clip Distance enabled 1: {}
                \\   | - Clip Distance enabled 2: {}
                \\   | - Clip Distance enabled 3: {}
                \\   | - Clip Distance enabled 4: {}
                \\   | - Clip Distance enabled 5: {}
                \\   | - Clip Distance enabled 6: {}
                \\   | - Clip Distance enabled 7: {}
                \\   | - Cull Distance enabled 0: {}
                \\   | - Cull Distance enabled 1: {}
                \\   | - Cull Distance enabled 2: {}
                \\   | - Cull Distance enabled 3: {}
                \\   | - Cull Distance enabled 4: {}
                \\   | - Cull Distance enabled 5: {}
                \\   | - Cull Distance enabled 6: {}
                \\   | - Cull Distance enabled 7: {}
                \\   | - Use Vertex Point Size: {}
                \\   | - Use Vertex Edge Flag: {}
                \\   | - Use Vertex Render Target Index: {}
                \\   | - Use Vertex Viewport Index: {}
                \\   | - Use Vertex Kill Flag: {}
                \\   | - VS Out Misc Vec enabled: {}
                \\   | - VS Out CCDist0 Vec enabled: {}
                \\   | - VS Out CCDist1 Vec enabled: {}
                \\   | - VS Out Misc Side Bus enabled: {}
                \\   | - Use Vertex GS Cut Flag: {}
                \\   | - Use Vertex Line Width: {}
                \\
            , .{
                @as(u32, @bitCast(regs.pa_cl_vs_out_cntl)),
                regs.pa_cl_vs_out_cntl.clip_dist_ena_0,
                regs.pa_cl_vs_out_cntl.clip_dist_ena_1,
                regs.pa_cl_vs_out_cntl.clip_dist_ena_2,
                regs.pa_cl_vs_out_cntl.clip_dist_ena_3,
                regs.pa_cl_vs_out_cntl.clip_dist_ena_4,
                regs.pa_cl_vs_out_cntl.clip_dist_ena_5,
                regs.pa_cl_vs_out_cntl.clip_dist_ena_6,
                regs.pa_cl_vs_out_cntl.clip_dist_ena_7,
                regs.pa_cl_vs_out_cntl.cull_dist_ena_0,
                regs.pa_cl_vs_out_cntl.cull_dist_ena_1,
                regs.pa_cl_vs_out_cntl.cull_dist_ena_2,
                regs.pa_cl_vs_out_cntl.cull_dist_ena_3,
                regs.pa_cl_vs_out_cntl.cull_dist_ena_4,
                regs.pa_cl_vs_out_cntl.cull_dist_ena_5,
                regs.pa_cl_vs_out_cntl.cull_dist_ena_6,
                regs.pa_cl_vs_out_cntl.cull_dist_ena_7,
                regs.pa_cl_vs_out_cntl.use_vtx_point_size,
                regs.pa_cl_vs_out_cntl.use_vtx_edge_flag,
                regs.pa_cl_vs_out_cntl.use_vtx_render_target_indx,
                regs.pa_cl_vs_out_cntl.use_vtx_viewport_indx,
                regs.pa_cl_vs_out_cntl.use_vtx_kill_flag,
                regs.pa_cl_vs_out_cntl.vs_out_misc_vec_ena,
                regs.pa_cl_vs_out_cntl.vs_out_ccdist0_vec_ena,
                regs.pa_cl_vs_out_cntl.vs_out_ccdist1_vec_ena,
                regs.pa_cl_vs_out_cntl.vs_out_misc_side_bus_ena,
                regs.pa_cl_vs_out_cntl.use_vtx_gs_cut_flag,
                regs.pa_cl_vs_out_cntl.use_vtx_line_width,
            });
        },
        .pixel => |psh| {
            try stdout.print(
                \\  GNM Pixel Shader:
                \\   | Number of input semantics: {}
                \\
            , .{psh.num_input_semantics});

            const regs = psh.registers;
            try stdout.print(
                \\  GNM Pixel Shader registers:
                \\   | SPI Shader Program Low: 0x{x}
                \\   | SPI Shader Program High: 0x{x}
                \\   | SPI Shader Resource 1 (0x{x}):
                \\   | - VGPRs: {}
                \\   | - SGPRs: {}
                \\   | - Priority: {}
                \\   | - Float mode: {t}
                \\   | - Priv: {}
                \\   | - DX10 clamp: {}
                \\   | - Debug mode: {}
                \\   | - IEEE mode: {}
                \\   | - CU group disable: {}
                \\   | - Cache control: {}
                \\   | - CDBG user: {}
                \\
            , .{
                regs.spi_shader_pgm_lo_ps,
                regs.spi_shader_pgm_hi_ps,

                @as(u32, @bitCast(regs.spi_shader_pgm_rsrc1_ps)),
                regs.spi_shader_pgm_rsrc1_ps.vgprs,
                regs.spi_shader_pgm_rsrc1_ps.sgprs,
                regs.spi_shader_pgm_rsrc1_ps.priority,
                regs.spi_shader_pgm_rsrc1_ps.float_mode,
                regs.spi_shader_pgm_rsrc1_ps.priv,
                regs.spi_shader_pgm_rsrc1_ps.dx10_clamp,
                regs.spi_shader_pgm_rsrc1_ps.debug_mode,
                regs.spi_shader_pgm_rsrc1_ps.ieee_mode,
                regs.spi_shader_pgm_rsrc1_ps.cu_group_disable,
                regs.spi_shader_pgm_rsrc1_ps.cache_ctl,
                regs.spi_shader_pgm_rsrc1_ps.cdbg_user,
            });
            try stdout.print(
                \\   | SPI Shader Resource 2 (0x{x}):
                \\   | - Scratch enabled: {}
                \\   | - User SGPR: {}
                \\   | - Trap present: {}
                \\   | - Wave count enabled: {}
                \\   | - Extra LDS size: {}
                \\   | - Exception enabled: 0x{x}
                \\   |   * Invalid: {}
                \\   |   * Input denormal: {}
                \\   |   * Divide by Zero: {}
                \\   |   * Overflow: {}
                \\   |   * Underflow: {}
                \\   |   * Inexact: {}
                \\   |   * Int divide by zero: {}
                \\   |   * Address watch: {}
                \\   |   * Memory violation: {}
                \\
            , .{
                @as(u32, @bitCast(regs.spi_shader_pgm_rsrc2_ps)),
                regs.spi_shader_pgm_rsrc2_ps.scratch_en,
                regs.spi_shader_pgm_rsrc2_ps.user_sgpr,
                regs.spi_shader_pgm_rsrc2_ps.trap_present,
                regs.spi_shader_pgm_rsrc2_ps.wave_cnt_en,
                regs.spi_shader_pgm_rsrc2_ps.extra_lds_size,
                @as(u9, @bitCast(regs.spi_shader_pgm_rsrc2_ps.excp_en)),
                regs.spi_shader_pgm_rsrc2_ps.excp_en.invalid,
                regs.spi_shader_pgm_rsrc2_ps.excp_en.input_denormal,
                regs.spi_shader_pgm_rsrc2_ps.excp_en.divide_by_zero,
                regs.spi_shader_pgm_rsrc2_ps.excp_en.overflow,
                regs.spi_shader_pgm_rsrc2_ps.excp_en.underflow,
                regs.spi_shader_pgm_rsrc2_ps.excp_en.inexact,
                regs.spi_shader_pgm_rsrc2_ps.excp_en.int_divide_by_zero,
                regs.spi_shader_pgm_rsrc2_ps.excp_en.address_watch,
                regs.spi_shader_pgm_rsrc2_ps.excp_en.memory_violation,
            });
            try stdout.print(
                \\   | SPI Shader Z Format (0x{x}):
                \\   | - Z export format: {t}
                \\   | SPI Shader Color Format 0x{x}):
                \\   | - Color 0 export format: {t}
                \\   | - Color 1 export format: {t}
                \\   | - Color 2 export format: {t}
                \\   | - Color 3 export format: {t}
                \\   | - Color 4 export format: {t}
                \\   | - Color 5 export format: {t}
                \\   | - Color 6 export format: {t}
                \\   | - Color 7 export format: {t}
                \\
            , .{
                @as(u32, @bitCast(regs.spi_shader_z_format)),
                regs.spi_shader_z_format.z_export_format,
                @as(u32, @bitCast(regs.spi_shader_col_format)),
                regs.spi_shader_col_format.col0_export_format,
                regs.spi_shader_col_format.col1_export_format,
                regs.spi_shader_col_format.col2_export_format,
                regs.spi_shader_col_format.col3_export_format,
                regs.spi_shader_col_format.col4_export_format,
                regs.spi_shader_col_format.col5_export_format,
                regs.spi_shader_col_format.col6_export_format,
                regs.spi_shader_col_format.col7_export_format,
            });
            try stdout.print(
                \\   | SPI PS Input Enabled (0x{x}):
                \\   | - Perspective sample enabled: {}
                \\   | - Perspective center enabled: {}
                \\   | - Perspective centroid enabled: {}
                \\   | - Perspective pull model enabled: {}
                \\   | - Linear sample enabled: {}
                \\   | - Linear center enabled: {}
                \\   | - Linear centroid enabled: {}
                \\   | - Line stipple tex enabled: {}
                \\   | - Position X float enabled: {}
                \\   | - Position Y float enabled: {}
                \\   | - Position Z float enabled: {}
                \\   | - Position W float enabled: {}
                \\   | - Front face enabled: {}
                \\   | - Ancillary enabled: {}
                \\   | - Sample coverage enabled: {}
                \\   | - Position fixed point enabled: {}
                \\
            , .{
                @as(u32, @bitCast(regs.spi_ps_input_ena)),
                regs.spi_ps_input_ena.persp_sample_ena,
                regs.spi_ps_input_ena.persp_center_ena,
                regs.spi_ps_input_ena.persp_centroid_ena,
                regs.spi_ps_input_ena.persp_pull_model_ena,
                regs.spi_ps_input_ena.linear_sample_ena,
                regs.spi_ps_input_ena.linear_center_ena,
                regs.spi_ps_input_ena.linear_centroid_ena,
                regs.spi_ps_input_ena.line_stipple_tex_ena,
                regs.spi_ps_input_ena.pos_x_float_ena,
                regs.spi_ps_input_ena.pos_y_float_ena,
                regs.spi_ps_input_ena.pos_z_float_ena,
                regs.spi_ps_input_ena.pos_w_float_ena,
                regs.spi_ps_input_ena.front_face_ena,
                regs.spi_ps_input_ena.ancillary_ena,
                regs.spi_ps_input_ena.sample_coverage_ena,
                regs.spi_ps_input_ena.pos_fixed_pt_ena,
            });
            try stdout.print(
                \\   | SPI PS Input Control (0x{x}):
                \\   | - Number of interpolations: {}
                \\   | - Parameter generation: {}
                \\   | - Is BC optimize disabled: {}
                \\
            , .{
                @as(u32, @bitCast(regs.spi_ps_in_control)),
                regs.spi_ps_in_control.num_interp,
                regs.spi_ps_in_control.param_gen,
                regs.spi_ps_in_control.bc_optimize_disable,
            });
            try stdout.print(
                \\   | SPI PS Input Address (0x{x}):
                \\   | - Offset: {}
                \\   | - Default value: {t}
                \\   | - Flat shade: {}
                \\   | - Cyl wrap: {}
                \\   | - Point sprite tex: {}
                \\   | - Duplicate: {}
                \\   | - FP16 interpolation mode: {}
                \\   | - Use default attr1: {}
                \\   | - Default value attr1: {t}
                \\   | - Point sprite tex attr1: {}
                \\   | - Is attr0 valid: {}
                \\   | - Is attr1 valid: {}
                \\
            , .{
                @as(u32, @bitCast(regs.spi_ps_input_addr)),
                regs.spi_ps_input_addr.offset,
                regs.spi_ps_input_addr.default_val,
                regs.spi_ps_input_addr.flat_shade,
                regs.spi_ps_input_addr.cyl_wrap,
                regs.spi_ps_input_addr.pt_sprite_tex,
                regs.spi_ps_input_addr.dup,
                regs.spi_ps_input_addr.fp16_interp_mode,
                regs.spi_ps_input_addr.use_default_attr1,
                regs.spi_ps_input_addr.default_val_attr1,
                regs.spi_ps_input_addr.pt_sprite_tex_attr1,
                regs.spi_ps_input_addr.attr0_valid,
                regs.spi_ps_input_addr.attr1_valid,
            });
            try stdout.print(
                \\   | SPI Barycentric Control 0x{x}):
                \\   | - Perspective center control: {}
                \\   | - Perspective centroid control: {}
                \\   | - Linear center control: {}
                \\   | - Linear centroid control: {}
                \\   | - Position float location: {}
                \\   | - Position float ULC: {}
                \\   | - Front face all bits: {}
                \\
            , .{
                @as(u32, @bitCast(regs.spi_baryc_cntl)),
                regs.spi_baryc_cntl.persp_center_cntl,
                regs.spi_baryc_cntl.persp_centroid_cntl,
                regs.spi_baryc_cntl.linear_center_cntl,
                regs.spi_baryc_cntl.linear_centroid_cntl,
                regs.spi_baryc_cntl.pos_float_location,
                regs.spi_baryc_cntl.pos_float_ulc,
                regs.spi_baryc_cntl.front_face_all_bits,
            });
            try stdout.print(
                \\   | Depth Buffer Shader Control (0x{x}):
                \\   | - Z export enable: {}
                \\   | - Stencil test value export enable: {}
                \\   | - Stencil operation value export enable: {}
                \\   | - Z order: {t}
                \\   | - Kill enable: {}
                \\   | - Coverage to mask enable: {}
                \\   | - Mask export enable: {}
                \\   | - Execute on HIER fail: {}
                \\   | - Execute on no-op: {}
                \\   | - Alpha to mask disable: {}
                \\   | - Depth before shader: {}
                \\   | - Conservative Z export: {t}
                \\
            , .{
                @as(u32, @bitCast(regs.db_shader_control)),
                regs.db_shader_control.z_export_enable,
                regs.db_shader_control.stencil_test_val_export_enable,
                regs.db_shader_control.stencil_op_val_export_enable,
                regs.db_shader_control.z_order,
                regs.db_shader_control.kill_enable,
                regs.db_shader_control.coverage_to_mask_enable,
                regs.db_shader_control.mask_export_enable,
                regs.db_shader_control.exec_on_hier_fail,
                regs.db_shader_control.exec_on_noop,
                regs.db_shader_control.alpha_to_mask_disable,
                regs.db_shader_control.depth_before_shader,
                regs.db_shader_control.conservative_z_export,
            });

            const cb_masks: [8]gnm.CbShaderMask.EnableMask = .{
                regs.cb_shader_mask.target0_enable,
                regs.cb_shader_mask.target1_enable,
                regs.cb_shader_mask.target2_enable,
                regs.cb_shader_mask.target3_enable,
                regs.cb_shader_mask.target4_enable,
                regs.cb_shader_mask.target5_enable,
                regs.cb_shader_mask.target6_enable,
                regs.cb_shader_mask.target7_enable,
            };
            try stdout.print(
                \\   | Color Buffer Shader Mask (0x{x}):
                \\
            , .{@as(u32, @bitCast(regs.cb_shader_mask))});
            inline for (cb_masks, 0..) |cbm, i| {
                try stdout.print(
                    \\   | - Target {} enable: 0x{x}
                    \\   |   * R: {}
                    \\   |   * G: {}
                    \\   |   * B: {}
                    \\   |   * A: {}
                    \\
                , .{ i, @as(u4, @bitCast(cbm)), cbm.r, cbm.g, cbm.b, cbm.a });
            }
        },
        .compute => |csh| {
            try stdout.print(
                \\  GNM Compute Shader:
                \\   | Version: {} 
                \\
            , .{
                csh.version,
            });

            if (csh.version == 0) {
                try stdout.print("   | Ordered append mode: {}\n", .{
                    csh.per_version.old.ordered_append_mode,
                });
            } else {
                try stdout.print(
                    \\   | Ordered append mode: {}
                    \\   | Number of input semantics: {}
                    \\
                , .{
                    csh.per_version.new.ordered_append_mode,
                    csh.per_version.new.num_input_semantics,
                });
            }

            const regs = csh.registers;
            try stdout.print(
                \\  GNM Compute Shader registers:
                \\   | Compute Program Low: 0x{x}
                \\   | Compute Program High: 0x{x}
                \\   | Compute Resource 1 (0x{x}):
                \\   | - VGPRs: {}
                \\   | - SGPRs: {}
                \\   | - Priority: {}
                \\   | - Float mode: {s}
                \\   | - Priv: {}
                \\   | - DX10 clamp: {}
                \\   | - Debug mode: {}
                \\   | - IEEE mode: {}
                \\   | - Bulky: {}
                \\   | - CDBG user: {}
                \\
            , .{
                regs.compute_pgm_lo,
                regs.compute_pgm_hi,

                @as(u32, @bitCast(regs.compute_pgm_rsrc1)),
                regs.compute_pgm_rsrc1.vgprs,
                regs.compute_pgm_rsrc1.sgprs,
                regs.compute_pgm_rsrc1.priority,
                @tagName(regs.compute_pgm_rsrc1.float_mode),
                regs.compute_pgm_rsrc1.priv,
                regs.compute_pgm_rsrc1.dx10_clamp,
                regs.compute_pgm_rsrc1.debug_mode,
                regs.compute_pgm_rsrc1.ieee_mode,
                regs.compute_pgm_rsrc1.bulky,
                regs.compute_pgm_rsrc1.cdbg_user,
            });
            try stdout.print(
                \\   | Compute Resource 2 (0x{x}):
                \\   | - Scratch enabled: {}
                \\   | - User SGPR: {}
                \\   | - Trap present: {}
                \\   | - TGID X enabled: {}
                \\   | - TGID Y enabled: {}
                \\   | - TGID Z enabled: {}
                \\   | - TG size enabled: {}
                \\   | - TIDIG comp count: {}
                \\   | - Exception enabled MSB: {}
                \\   | - LDS size: {}
                \\   | - Exception enabled: 0x{x}
                \\   |   * Invalid: {}
                \\   |   * Input denormal: {}
                \\   |   * Divide by Zero: {}
                \\   |   * Overflow: {}
                \\   |   * Underflow: {}
                \\   |   * Inexact: {}
                \\   |   * Int divide by zero: {}
                \\
            , .{
                @as(u32, @bitCast(regs.compute_pgm_rsrc2)),
                regs.compute_pgm_rsrc2.scratch_en,
                regs.compute_pgm_rsrc2.user_sgpr,
                regs.compute_pgm_rsrc2.trap_present,
                regs.compute_pgm_rsrc2.tgid_x_en,
                regs.compute_pgm_rsrc2.tgid_y_en,
                regs.compute_pgm_rsrc2.tgid_z_en,
                regs.compute_pgm_rsrc2.tg_size_en,
                regs.compute_pgm_rsrc2.tidig_comp_cnt,
                regs.compute_pgm_rsrc2.excp_en_msb,
                regs.compute_pgm_rsrc2.lds_size,
                @as(u7, @bitCast(regs.compute_pgm_rsrc2.excp_en)),
                regs.compute_pgm_rsrc2.excp_en.invalid,
                regs.compute_pgm_rsrc2.excp_en.input_denormal,
                regs.compute_pgm_rsrc2.excp_en.divide_by_zero,
                regs.compute_pgm_rsrc2.excp_en.overflow,
                regs.compute_pgm_rsrc2.excp_en.underflow,
                regs.compute_pgm_rsrc2.excp_en.inexact,
                regs.compute_pgm_rsrc2.excp_en.int_divide_by_zero,
            });

            try stdout.print(
                \\   | Compute Number of Threads X (0x{x}):
                \\   | - Number of full threads: {}
                \\   | - Number of partial threads: {}
                \\   | Compute Number of Threads Y (0x{x}):
                \\   | - Number of full threads: {}
                \\   | - Number of partial threads: {}
                \\   | Compute Number of Threads Z (0x{x}):
                \\   | - Number of full threads: {}
                \\   | - Number of partial threads: {}
                \\
            , .{
                @as(u32, @bitCast(regs.compute_num_thread_x)),
                regs.compute_num_thread_x.num_thread_full,
                regs.compute_num_thread_x.num_thread_partial,
                @as(u32, @bitCast(regs.compute_num_thread_y)),
                regs.compute_num_thread_y.num_thread_full,
                regs.compute_num_thread_y.num_thread_partial,
                @as(u32, @bitCast(regs.compute_num_thread_z)),
                regs.compute_num_thread_z.num_thread_full,
                regs.compute_num_thread_z.num_thread_partial,
            });
        },
        else => @panic("TODO"),
    }

    for (sh.resource_slots) |r| {
        try stdout.print(
            \\  Resource slot:
            \\   | Usage type: {t}
            \\   | API slot: {} 
            \\   | Start register: {}
            \\
        , .{
            r.usage_type,
            r.api_slot,
            r.start_register,
        });
    }

    switch (sh.inputs) {
        .vertex, .compute => |inputs| {
            for (inputs) |vi| {
                try stdout.print(
                    \\  Vertex input:
                    \\   | Semantic: {}
                    \\   | VGPR: {} 
                    \\   | Size in elements: {}
                    \\
                , .{
                    vi.semantic,
                    vi.vgpr,
                    vi.size_in_elements,
                });
            }
        },
        .pixel => |inputs| {
            for (inputs) |pi| {
                try stdout.print(
                    \\  Pixel pi:
                    \\   | Semantic: {}
                    \\   | Flat shade: {}
                    \\   | Sel linear: {}
                    \\
                , .{
                    pi.semantic,
                    pi.flat_shade,
                    pi.sel_linear,
                });

                if (pi.hw.neo.interp_f16.low or pi.hw.neo.interp_f16.low) {
                    try stdout.print(
                        \\   | Default value f16_lo: {t} 
                        \\   | Default value f16_hi: {t} 
                        \\   | Interpolate F16 type: {s}
                        \\
                    , .{
                        pi.default_value,
                        pi.hw.neo.default_value_f16hi,
                        if (pi.hw.neo.interp_f16.low and pi.hw.neo.interp_f16.high)
                            "f16_lohi"
                        else if (pi.hw.neo.interp_f16.low)
                            "f16_lo"
                        else if (pi.hw.neo.interp_f16.high)
                            "f16_hi"
                        else
                            "b32",
                    });
                } else {
                    try stdout.print(
                        \\   | Default value: {t} 
                        \\   | Custom: {}
                        \\
                    , .{
                        pi.default_value,
                        pi.hw.base.custom,
                    });
                }
            }
        },
        else => @panic("TODO"),
    }

    const ref = sh.parseReflection(arena, &file_reader.interface) catch |err| {
        return fatal("Failed to parse reflection data with {t}!", .{err});
    };

    const sbi = ref.binary_info;
    try stdout.print(
        \\  GNM Shader Binary Info:
        \\   | Magic/Signature: {x}
        \\   | Version: {} 
        \\   | Is PSSL or CG: {}
        \\   | Is Source Cached: {}
        \\   | Shader type: {t}
        \\   | Shader byte length: {} 
        \\   | Chunk usage base offset in DWORDs: {} 
        \\   | Number of input usage slots: {} 
        \\   | Has shader resource table (SRT): {} 
        \\   | Is SRT used info valid: {} 
        \\   | Has extended usage info: {} 
        \\   | Source hash type: {} 
        \\   | Footer version: {} 
        \\   | Association hash: {x} {x} 
        \\   | CRC32: {x}
        \\
    , .{
        sbi.magic,
        sbi.version,
        sbi.info.is_pssl_or_cg,
        sbi.info.is_source_cached,
        sbi.info.type,
        sbi.info.length,
        sbi.chunk_usage_base_offset_dwords,
        sbi.num_input_usage_slots,
        sbi.srt.has_extended_usage_info,
        sbi.srt.is_srt_used_info_valid,
        sbi.srt.has_extended_usage_info,
        sbi.srt.source_hash_type,
        sbi.footer_version,
        sbi.association_hash[0],
        sbi.association_hash[1],
        sbi.crc32,
    });

    try stdout.print(
        \\Parameters Info:
        \\ | Number of buffer resources: {}
        \\ | Number of constants: {}
        \\ | Number of variables/elements: {}
        \\ | Number of sampler resources: {}
        \\ | Number of input attributes: {}
        \\ | Number of output attributes: {}
        \\ | Number of stream outs: {}
        \\ | Value table byte length: 0x{x}
        \\ | String table byte length: 0x{x}
        \\
    , .{
        ref.buffers.len,
        ref.constants.len,
        ref.elements.len,
        ref.samplers.len,
        ref.inputs.len,
        ref.outputs.len,
        ref.stream_outs.len,
        ref.value_table.len,
        ref.string_table.len,
    });

    for (ref.buffers) |b| {
        try stdout.print(
            \\  Buffer resource:
            \\   | Name: {s}
            \\   | Resource index: {}
            \\   | Stride byte length: {}
            \\   | Buffer type: {t}
            \\   | Internal buffer type: {t}
            \\   | Type: {t}
            \\   | Number of sub elements: {}
            \\   | Offset to first sub element: {}
            \\
        , .{
            b.getName(ref.string_table),
            b.resource_index,
            b.stride_byte_len,
            b.buffer_type,
            b.internal_buffer_type,
            b.type,
            b.num_sub_elements,
            b.first_sub_element_offset,
        });
    }

    for (ref.constants) |c| {
        try stdout.print(
            \\  Constant:
            \\   | Name: {s}
            \\   | Element offset: {}
            \\   | Register index: {}
            \\   | Constant buffer index: {}
            \\   | Element type: {t}
            \\   | Constant buffer type: {t}
            \\   | Default values: {}
            \\
        , .{
            c.getName(ref.string_table),
            c.element_offset,
            c.register_index,
            c.constant_buffer_index,
            c.element_type,
            c.constant_buffer_type,
            c.default_values,
        });
    }

    for (ref.elements) |elem| {
        try stdout.print(
            \\  Element/Variable:
            \\   | Name: {s}
            \\   | Type Name: {s}
            \\   | Is used: {}
            \\   | Is row major: {}
            \\   | Is pointer: {}
            \\   | Element type: {t}
            \\   | Element class: {t}
            \\   | Byte offset: 0x{x}
            \\   | Byte length: 0x{x}
            \\   | Array length: 0x{x}
            \\   | Number of sub elements: {}
            \\   | Offset to first sub element: {}
            \\
        , .{
            elem.getName(ref.string_table),
            elem.getTypeName(ref.string_table),
            elem.attributes.is_used,
            elem.attributes.is_row_major,
            elem.attributes.is_pointer,
            elem.element_type,
            elem.element_class,
            elem.byte_offset,
            elem.byte_length,
            elem.array_length,
            elem.num_sub_elements,
            elem.first_sub_element_offset,
        });
        if (elem.element_class == .constant_buffer_element) {
            try stdout.print("   | Default value index: {}\n", .{
                elem.default.value_index,
            });
        } else {
            try stdout.print("   | Resource index: {}\n", .{
                elem.default.resource_index,
            });
        }
    }

    for (ref.samplers) |s| {
        try stdout.print(
            \\  Sampler:
            \\   | Name: {s}
            \\   | Resource index: {}
            \\
        , .{
            s.getName(ref.string_table),
            s.resource_index,
        });
    }

    for (ref.inputs) |i| {
        try stdout.print(
            \\  Input:
            \\   | Name: {s}
            \\   | Type: {t}
            \\   | Semantic Name: {s}
            \\   | Semantic index: {}
            \\   | Resource index: {}
            \\   | Interpolation type: {t}
            \\   | Stream number: {}
            \\
        , .{
            i.getName(ref.string_table),
            i.type,
            i.getSemanticName(ref.string_table),
            i.semantic_index,
            i.resource_index,
            i.interpolation_type,
            i.stream_number,
        });
    }

    for (ref.outputs) |o| {
        try stdout.print(
            \\  Output:
            \\   | Name: {s}
            \\   | Type: {t}
            \\   | Semantic Name: {s}
            \\   | Semantic index: {}
            \\   | Resource index: {}
            \\   | Interpolation type: {t}
            \\   | Stream number: {}
            \\
        , .{
            o.getName(ref.string_table),
            o.type,
            o.getSemanticName(ref.string_table),
            o.semantic_index,
            o.resource_index,
            o.interpolation_type,
            o.stream_number,
        });
    }

    for (ref.stream_outs) |s| {
        try stdout.print(
            \\  Stream Out:
            \\   | Semantic Name: {s}
            \\   | Semantic index: {}
            \\   | Semantic: {t}
            \\   | Stride: 0x{x}
            \\   | Offset: 0x{x}
            \\   | Slot: {}
            \\   | Stream: {}
            \\   | Components: {t}
            \\
        , .{
            s.getSemanticName(ref.string_table),
            s.semantic_index,
            s.semantic,
            s.stride,
            s.offset,
            s.slot,
            s.stream,
            s.components,
        });
    }

    try stdout.print(
        \\
        \\GCN code instructions:
        \\
    , .{});

    var decoder = gcn.Decoder.init(sh.gcn_code);
    while (decoder.nextInstruction()) |maybe_instr| {
        const instr = maybe_instr orelse break;
        var string_buf: [256:0]u8 = undefined;
        const instr_str = instr.format(&string_buf) catch |err| {
            try stderr.print("{x:08}: Failed to format instruction with {t}\n", .{
                instr.offset,
                err,
            });
            continue;
        };
        try stdout.print("{x:08}: {s}\n", .{ instr.offset, instr_str });
    } else |err| {
        try stderr.print("Failed to decode current instruction with {t}\n", .{err});
    }

    if (gcn.Analyzer.scan(arena, sh.gcn_code, .{})) |analysis| {
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
        }
    } else |err| {
        try stderr.print("Failed to analyze shader with {t}\n", .{err});
    }
}
