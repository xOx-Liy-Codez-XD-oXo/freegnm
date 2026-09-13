pub const Shader = @import("psb/shader.zig");

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

pub const ShaderType = enum(u8) {
    vertex = 0,
    fragment = 1,
    compute = 2,
    geometry = 3,
    hull = 4,
    domain = 5,
};

pub const SourceCodeType = enum(u8) {
    il = 0,
    isa = 1,
    scu = 2,
};

pub const CompilerType = enum(u4) {
    unspecified = 0,
    orbis_psslc = 1,
    orbis_esslc = 2,
    orbis_wave = 3,
    orbis_cu_as = 4,
};

pub const VertexVariant = enum(u8) {
    vertex = 0,
    @"export" = 1,
    local = 2,
    dispatch_draw = 3,
    export_on_chip = 4,
};

pub const DomainVariant = enum(u8) {
    vertex = 0,
    @"export" = 1,
    vertex_hs_off_chip = 2,
    export_hs_off_chip = 3,
    vertex_hs_dynamic = 4,
    export_hs_dynamic = 5,
    export_on_chip = 6,
};

pub const GeometryVariant = enum(u8) {
    off_chip = 0,
    on_chip = 1,
};

pub const HullVariant = enum(u8) {
    on_chip = 0,
    off_chip = 1,
    dynamic = 2,
};

pub const Type = enum(u8) {
    float1 = 0,
    float2 = 1,
    float3 = 2,
    float4 = 3,
    half1 = 4,
    half2 = 5,
    half3 = 6,
    half4 = 7,
    int1 = 8,
    int2 = 9,
    int3 = 10,
    int4 = 11,
    uint1 = 12,
    uint2 = 13,
    uint3 = 14,
    uint4 = 15,
    double1 = 16,
    double2 = 17,
    double3 = 18,
    double4 = 19,
    float1x1 = 20,
    float2x1 = 21,
    float3x1 = 22,
    float4x1 = 23,
    float1x2 = 24,
    float2x2 = 25,
    float3x2 = 26,
    float4x2 = 27,
    float1x3 = 28,
    float2x3 = 29,
    float3x3 = 30,
    float4x3 = 31,
    float1x4 = 32,
    float2x4 = 33,
    float3x4 = 34,
    float4x4 = 35,
    half1x1 = 36,
    half2x1 = 37,
    half3x1 = 38,
    half4x1 = 39,
    half1x2 = 40,
    half2x2 = 41,
    half3x2 = 42,
    half4x2 = 43,
    half1x3 = 44,
    half2x3 = 45,
    half3x3 = 46,
    half4x3 = 47,
    half1x4 = 48,
    half2x4 = 49,
    half3x4 = 50,
    half4x4 = 51,
    int1x1 = 52,
    int2x1 = 53,
    int3x1 = 54,
    int4x1 = 55,
    int1x2 = 56,
    int2x2 = 57,
    int3x2 = 58,
    int4x2 = 59,
    int1x3 = 60,
    int2x3 = 61,
    int3x3 = 62,
    int4x3 = 63,
    int1x4 = 64,
    int2x4 = 65,
    int3x4 = 66,
    int4x4 = 67,
    uint1x1 = 68,
    uint2x1 = 69,
    uint3x1 = 70,
    uint4x1 = 71,
    uint1x2 = 72,
    uint2x2 = 73,
    uint3x2 = 74,
    uint4x2 = 75,
    uint1x3 = 76,
    uint2x3 = 77,
    uint3x3 = 78,
    uint4x3 = 79,
    uint1x4 = 80,
    uint2x4 = 81,
    uint3x4 = 82,
    uint4x4 = 83,
    double1x1 = 84,
    double2x1 = 85,
    double3x1 = 86,
    double4x1 = 87,
    double1x2 = 88,
    double2x2 = 89,
    double3x2 = 90,
    double4x2 = 91,
    double1x3 = 92,
    double2x3 = 93,
    double3x3 = 94,
    double4x3 = 95,
    double1x4 = 96,
    double2x4 = 97,
    double3x4 = 98,
    double4x4 = 99,
    point = 100,
    line = 101,
    triangle = 102,
    adjacent_line = 103,
    adjacent_triangle = 104,
    patch = 105,
    structure = 106,
    long1 = 107,
    long2 = 108,
    long3 = 109,
    long4 = 110,
    ulong1 = 111,
    ulong2 = 112,
    ulong3 = 113,
    ulong4 = 114,
    long1x1 = 115,
    long2x1 = 116,
    long3x1 = 117,
    long4x1 = 118,
    long1x2 = 119,
    long2x2 = 120,
    long3x2 = 121,
    long4x2 = 122,
    long1x3 = 123,
    long2x3 = 124,
    long3x3 = 125,
    long4x3 = 126,
    long1x4 = 127,
    long2x4 = 128,
    long3x4 = 129,
    long4x4 = 130,
    ulong1x1 = 131,
    ulong2x1 = 132,
    ulong3x1 = 133,
    ulong4x1 = 134,
    ulong1x2 = 135,
    ulong2x2 = 136,
    ulong3x2 = 137,
    ulong4x2 = 138,
    ulong1x3 = 139,
    ulong2x3 = 140,
    ulong3x3 = 141,
    ulong4x3 = 142,
    ulong1x4 = 143,
    ulong2x4 = 144,
    ulong3x4 = 145,
    ulong4x4 = 146,
    bool1 = 147,
    bool2 = 148,
    bool3 = 149,
    bool4 = 150,
    texture = 151,
    sampler_state = 152,
    buffer = 153,
    ushort1 = 154,
    ushort2 = 155,
    ushort3 = 156,
    ushort4 = 157,
    uchar1 = 158,
    uchar2 = 159,
    uchar3 = 160,
    uchar4 = 161,
    short1 = 162,
    short2 = 163,
    short3 = 164,
    short4 = 165,
    char1 = 166,
    char2 = 167,
    char3 = 168,
    char4 = 169,
    void = 170,
    texture_r128 = 171,
};

pub const BufferType = enum(u8) {
    data_buffer = 0,
    texture_1d = 1,
    texture_2d = 2,
    texture_3d = 3,
    texture_cube = 4,
    texture_1d_array = 5,
    texture_2d_array = 6,
    texture_cube_array = 7,
    ms_texture_2d = 8,
    ms_texture_2d_array = 9,
    regular_buffer = 10,
    byte_buffer = 11,
    rw_databuffer = 12,
    rw_texture_1d = 13,
    rw_texture_2d = 14,
    rw_texture_3d = 15,
    rw_texture_1d_array = 16,
    rw_texture_2d_array = 17,
    rw_regular_buffer = 18,
    rw_byte_buffer = 19,
    append_buffer = 20,
    consume_buffer = 21,
    constant_buffer = 22,
    texture_buffer = 23,
    point_buffer = 24,
    line_buffer = 25,
    triangle_buffer = 26,
    srt_buffer = 27,
    dispatch_draw_buffer = 28,
    rw_texture_cube = 29,
    rw_texture_cube_array = 30,
    rw_ms_texture_2d = 31,
    rw_ms_texture_2d_array = 32,
    texture_1d_r128 = 33,
    texture_2d_r128 = 34,
    ms_texture_2d_r128 = 35,
    rw_texture_1d_r128 = 36,
    rw_texture_2d_r128 = 37,
    rw_ms_texture_2d_r128 = 38,
};

pub const InternalBufferType = enum(u8) {
    uav = 0,
    srv = 1,
    lds = 2,
    gds = 3,
    cbuffer = 4,
    texture_sampler = 5,
    internal = 6,
};

pub const ElementClass = enum(u8) {
    element = 0,
    buffer_element = 1,
    sampler_state_element = 2,
    constant_buffer_element = 3,
};

pub const Semantic = enum(u8) {
    position = 0,
    normal = 1,
    color = 2,
    binormal = 3,
    tangent = 4,
    texcoord0 = 5,
    texcoord1 = 6,
    texcoord2 = 7,
    texcoord3 = 8,
    texcoord4 = 9,
    texcoord5 = 10,
    texcoord6 = 11,
    texcoord7 = 12,
    texcoord8 = 13,
    texcoord9 = 14,
    texcoord_end = 15,
    implicit = 16,
    non_referencable = 17,
    clip = 18,
    fog = 19,
    s_point_size = 20,
    frag_coord = 21,
    target0 = 22,
    target1 = 23,
    target2 = 24,
    target3 = 25,
    target4 = 26,
    target5 = 27,
    target6 = 28,
    target7 = 29,
    target8 = 30,
    target9 = 31,
    target10 = 32,
    target11 = 33,
    depth = 34,
    last_cg = 35,
    user_defined = 36,
    s_clip_distance = 37,
    s_cull_distance = 38,
    s_coverage = 39,
    s_depth_output = 40,
    s_dispatch_thread_id = 41,
    s_domain_location = 42,
    s_group_id = 43,
    s_group_index = 44,
    s_group_thread_id = 45,
    s_position = 46,
    s_vertex_id = 47,
    s_instance_id = 48,
    s_sample_index = 49,
    s_primitive_id = 50,
    s_gs_instance_id = 51,
    s_output_control_point_id = 52,
    s_front_face = 53,
    s_render_target_index = 54,
    s_viewport_index = 55,
    s_target_output = 56,
    s_edge_tess_factor = 57,
    s_inside_tess_factor = 58,
    s_point_coord = 59,
    s_depth_ge_output = 60,
    s_depth_le_output = 61,
    s_vertex_offset_id = 62,
    s_instance_offset_id = 63,
    s_stencil_value = 64,
    s_stencil_op = 65,
};

pub const FragmentInterpType = enum(u8) {
    none = 0,
    linear = 1,
    point = 2,
};

pub const DomainPatchType = enum(u8) {
    isoline = 0,
    tri = 1,
    quad = 2,
};

pub const DomainTopologyType = enum(u8) {
    point = 0,
    line = 1,
    cw_tri = 2,
    ccw_tri = 3,
};

pub const DomainPartitioningType = enum(u8) {
    integer = 0,
    power_of_2 = 1,
    odd_factorial = 2,
    even_factorial = 3,
};

pub const ComponentMask = enum(u8) {
    none = 0,
    x = 1,
    y = 2,
    xy = 3,
    z = 4,
    xz = 5,
    yz = 6,
    xyz = 7,
    w = 8,
    xw = 9,
    yw = 10,
    xyw = 11,
    zw = 12,
    xzw = 13,
    yzw = 14,
    xyzw = 15,
};

pub const BinaryHeader = extern struct {
    version: extern struct {
        major: u8,
        minor: u8,
        compiler: u16,
    },

    association_hash: [2]u32,

    type: ShaderType,
    source_code_type: SourceCodeType,
    uses_shader_resource_table: bool,
    compiler: packed struct(u8) {
        type: CompilerType,
        _: u4 = 0,
    },

    code_byte_length: u32,

    variant: extern struct {
        vs: VertexVariant = .vertex,
        ds: DomainVariant = .vertex,
        gs: GeometryVariant = .off_chip,
        hs: HullVariant = .on_chip,
    },

    attributes: extern union {
        cs: extern struct {
            num_threads: [3]u16,
            _: [6]u8 = @splat(0),
        },
        gs: extern struct {
            instance: u16,
            max_vertex_count: u16,
            input_type: Type,
            output_type: BufferType,
            _: [6]u8 = @splat(0),
        },
        hs: extern struct {
            domain_patch: DomainPatchType,
            input_control_points: u8,
            output_topology: DomainTopologyType,
            partitioning: DomainPartitioningType,

            output_control_points: u8,
            patch_size: u8,
            _: [2]u8 = @splat(0),

            max_tess_factor: f32,
        },
        ds: extern struct {
            domain_patch: DomainPatchType,
            input_control_points: u8,
            _: [10]u8 = @splat(0),
        },
        none: extern struct {
            _: [12]u8 = @splat(0),
        },
    },
};

pub const ParamInfo = extern struct {
    num_buffer_resources: u32,
    num_constants: u32,
    num_variables: u32,
    num_sampler_resources: u32,

    num_input_attributes: u8,
    num_output_attributes: u8,
    num_stream_outs: u8,
    _: u8 = 0,

    value_table_byte_len: u32,
    string_table_byte_len: u32,
};

pub const Buffer = extern struct {
    resource_index: u32,
    stride_byte_len: u32,

    buffer_type: BufferType,
    internal_buffer_type: InternalBufferType,
    type: Type,
    _: u8 = 0,

    num_sub_elements: u32,
    first_sub_element_offset: u32,

    name_table_offset: u32,

    pub fn getName(self: Buffer, string_table: [:0]const u8) []const u8 {
        return mem.sliceTo(string_table[self.name_table_offset..], 0);
    }
};

pub const Constant = extern struct {
    element_offset: u32,
    register_index: u32,

    constant_buffer_index: u8,
    element_type: Type,
    constant_buffer_type: BufferType,
    _: u8 = 0,

    default_values: extern union {
        as_f32: [4]f32,
        as_i32: [4]i32,
        as_u32: [4]u32,
    },

    name_table_offset: u32,

    pub fn getName(self: Constant, string_table: [:0]const u8) []const u8 {
        return mem.sliceTo(string_table[self.name_table_offset..], 0);
    }
};

pub const Element = extern struct {
    element_type: Type align(1),
    attributes: packed struct(u16) {
        is_used: bool,
        is_row_major: bool,
        _: u6 = 0,
        is_pointer: bool,
        _2: u7 = 0,
    } align(1),
    element_class: ElementClass align(1),

    byte_offset: u32,
    byte_length: u32,
    array_length: u32,

    default: extern union {
        value_index: u32,
        resource_index: u32,
    },

    num_sub_elements: u32,
    first_sub_element_offset: u32,

    name_table_offset: u32,
    type_name_table_offset: u32,

    pub fn getName(self: Element, string_table: [:0]const u8) []const u8 {
        return mem.sliceTo(string_table[self.name_table_offset..], 0);
    }
    pub fn getTypeName(self: Element, string_table: [:0]const u8) []const u8 {
        return mem.sliceTo(string_table[self.name_table_offset..], 0);
    }
};

pub const SamplerState = extern struct {
    _: u64 = 0,
    resource_index: u32,
    name_table_offset: u32,

    pub fn getName(self: SamplerState, string_table: [:0]const u8) []const u8 {
        return mem.sliceTo(string_table[self.name_table_offset..], 0);
    }
};

pub const Attribute = extern struct {
    type: Type,
    semantic: Semantic,
    semantic_index: u8,
    resource_index: u8,

    interpolation_type: FragmentInterpType,
    stream_number: u8,
    _: u16 = 0,

    name_table_offset: u32,
    semantic_name_table_offset: u32,

    pub fn getName(self: Attribute, string_table: [:0]const u8) []const u8 {
        return mem.sliceTo(string_table[self.name_table_offset..], 0);
    }
    pub fn getSemanticName(self: Attribute, string_table: [:0]const u8) []const u8 {
        return mem.sliceTo(string_table[self.semantic_name_table_offset..], 0);
    }
};

pub const StreamOut = extern struct {
    stride: u16,
    offset: u16,
    semantic_index: u8,
    slot: u8,
    stream: u8,
    semantic: Semantic,
    components: ComponentMask,

    semantic_name_table_offset: u32,

    pub fn getSemanticName(self: StreamOut, string_table: [:0]const u8) []const u8 {
        return mem.sliceTo(string_table[self.semantic_name_table_offset..], 0);
    }
};

comptime {
    assert(@sizeOf(BinaryHeader) == 0x24);
    assert(@sizeOf(ParamInfo) == 0x1c);
    assert(@sizeOf(Buffer) == 0x18);
    assert(@sizeOf(Constant) == 0x20);
    assert(@sizeOf(Element) == 0x24);
    assert(@sizeOf(SamplerState) == 0x10);
    assert(@sizeOf(Attribute) == 0x10);
    assert(@sizeOf(StreamOut) == 0x10);
}
