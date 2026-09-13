const std = @import("std");
const log = std.log;
const mem = std.mem;

const gnm = @import("gnm.zig");

pub const TilingParams = struct {
    tile_mode: gnm.TileMode,
    min_gpu_mode: gnm.GpuMode,
    linear_width: u32,
    linear_height: u32,
    linear_depth: u32,
    num_fragments_per_pixel: u32,
    base_tiled_pitch: u32,
    mip_level: u32,
    array_slice: u32,
    surface_flags: packed struct(u32) {
        color_target: bool = false,
        depth_target: bool = false,
        stencil_target: bool = false,
        texture: bool = false,
        cube: bool = false,
        volume: bool = false,
        fmask: bool = false,
        cube_as_array: bool = false,
        overlay: bool = false,
        display: bool = false,
        prt: bool = false,
        power_of_2_pad: bool = false,
        tex_compatible: bool = false,
        _: u19 = 0,
    },
    bits_per_fragment: u32,
    is_block_compressed: bool,
};

pub const TileInfo = extern struct {
    array_mode: c_int,
    num_banks: c_int,
    bank_width: c_int,
    bank_height: c_int,
    macro_tile_aspect: c_int,
    tile_split: c_int,
    pipe_config: c_int,
};

pub const SurfaceType = enum(c_int) {
    color_display,
    color,
    depth_stencil,
    depth,
    stencil,
    fmask,
    texture_flat,
    texture_volume,
    texture_cubemap,
    rw_texture_flat,
    rw_texture_volume,
    rw_texture_cubemap,
};

pub const SurfaceInfo = extern struct {
    pitch: u32,
    height: u32,
    depth: u32,
    surface_byte_len: u64,
    base_alignment: u32,
    pitch_alignment: u32,
    height_alignment: u32,
    depth_alignment: u32,
    bits_per_element: u32,
    block_width: u32,
    block_height: u32,
    // tile_mode: gnm.TileMode,
    tile_mode: c_int, // FIXME
    tile_info: TileInfo,
    flags: packed struct(u32) {
        tex_compatible: bool,
        _: u31,
    },
};

pub const SurfaceProperties = extern struct {
    // tile_mode: gnm.TileMode,
    tile_mode: c_int, // FIXME
    flags: packed struct(u32) {
        color_target: bool,
        depth_target: bool,
        stencil_target: bool,
        texture: bool,
        cube: bool,
        volume: bool,
        fmask: bool,
        cube_as_array: bool,
        overlay: bool,
        display: bool,
        prt: bool,
        pow_to_pad: bool,
        tex_compatible: bool,
        _: u19,
    },
};

pub const TextureInfo = extern struct {
    // type: gnm.TextureType, // FIXME
    type: c_int,
    format: gnm.DataFormat,
    width: u32,
    height: u32,
    pitch: u32,
    depth: u32,
    num_fragments: u32,
    num_mips: u32,
    num_slices: u32,
    // tile_mode: gnm.TileMode, // FIXME
    tile_mode: c_int,
    // min_gpu_mode: gnm.GpuMode, // FIXME
    min_gpu_mode: c_int,
    power_of_two_pad: bool,
};

pub const Error = error{
    SomeError,
};

extern fn gpaStrError(err: c_int) [*c]const u8;

const TilingParamsInternal = extern struct {
    // tile_mode: gnm.TileMode, // FIXME
    tile_mode: c_uint,
    // min_gpu_mode: gnm.GpuMode, // FIXME
    min_gpu_mode: c_uint,
    linear_width: u32,
    linear_height: u32,
    linear_depth: u32,
    num_fragments_per_pixel: u32,
    base_tiled_pitch: u32,
    mip_level: u32,
    array_slice: u32,
    surface_flags: u32,
    bits_per_fragment: u32,
    is_block_compressed: bool,
};

extern fn gpaComputeSurfaceInfo(out: *SurfaceInfo, tp: *const TilingParamsInternal) c_int;
pub fn computeSurfaceInfo(tiling_params: TilingParams) Error!SurfaceInfo {
    var info: SurfaceInfo = undefined;

    const tp: TilingParamsInternal = .{
        .tile_mode = @backingInt(tiling_params.tile_mode),
        .min_gpu_mode = @backingInt(tiling_params.min_gpu_mode),
        .linear_width = tiling_params.linear_width,
        .linear_height = tiling_params.linear_height,
        .linear_depth = tiling_params.linear_depth,
        .num_fragments_per_pixel = tiling_params.num_fragments_per_pixel,
        .base_tiled_pitch = tiling_params.base_tiled_pitch,
        .mip_level = tiling_params.mip_level,
        .array_slice = tiling_params.array_slice,
        .surface_flags = @backingInt(tiling_params.surface_flags),
        .bits_per_fragment = tiling_params.bits_per_fragment,
        .is_block_compressed = tiling_params.is_block_compressed,
    };

    const result = gpaComputeSurfaceInfo(&info, &tp);
    if (result != 0) {
        log.err("gpaComputeSurfaceInfo failed with {s}", .{gpaStrError(result)});
        return error.SomeError;
    }
    return info;
}

extern fn gpaFindOptimalSurface(
    outprops: *SurfaceProperties,
    surfacetype: SurfaceType,
    bpp: u32,
    numfrags: u32,
    mipmapped: bool,
    mingpumode: c_int,
) c_int;
pub fn findOptimalSurface(
    surface_type: SurfaceType,
    bits_per_pixel: u32,
    num_fragments: u32,
    is_mip_mapped: bool,
    min_gpu_mode: gnm.GpuMode,
) Error!SurfaceProperties {
    var props: SurfaceProperties = undefined;
    const result = gpaFindOptimalSurface(
        &props,
        surface_type,
        bits_per_pixel,
        num_fragments,
        is_mip_mapped,
        @backingInt(min_gpu_mode),
    );
    if (result != 0) {
        log.err("gpaTileTextureAll failed with {s}", .{gpaStrError(result)});
        return error.SomeError;
    }
    return props;
}

extern fn gpaTileTextureAll(
    inbuf: *const anyopaque,
    inlen: usize,
    outbuf: *anyopaque,
    outlen: usize,
    texinfo: *const TextureInfo,
    newtiling: c_int,
) c_int;
pub fn tileTextureAll(
    input: []const u8,
    output: []u8,
    tex_info: TextureInfo,
    new_tile_mode: gnm.TileMode,
) Error!void {
    const result = gpaTileTextureAll(
        input.ptr,
        input.len,
        output.ptr,
        output.len,
        &tex_info,
        @backingInt(new_tile_mode),
    );
    if (result != 0) {
        log.err("gpaTileTextureAll failed with {s}", .{gpaStrError(result)});
        return error.SomeError;
    }
}
