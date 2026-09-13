# freegnm

freegnm is an ***in development*** library for accessing hardware accelerated graphics and compute on the PlayStation 4, and a set of tools for manipulating resources related to it.

One of its goals is to provide functionality comparable to the official (and proprietary) GNM library.

Find code usage examples at [freegnm-examples](https://github.com/lateleite/freegnm-examples).

Want to use the old C codebase instead? [Use the 'c' branch](https://github.com/lateleite/freegnm/tree/c)

**Caveats:** 

- Much of the functionality is missing
- Any and all API may change
- This hasn't been tested on a Pro/NEO model PlayStation 4
- The codebase is currently in a Zig re-write/clean-up

**Tools available:**

- gcn-dis - a GCN shader code disassembler
- gnf-conv - a GNF texture to BMP/PNG/KTX converter
- gnf-info - displays information about a GNF texture
- gnf-mk - a GNF texture creator
- pm4-dis - a PM4 packet disassembler
- psb-dis - a PlayStation shader binary file disassembler and information dumper

## Building as a standalone library

Get Zig 0.17.0-dev, and run:

```sh
zig build --release=fast
```

If successful, you'll have your new library and tools inside the `zig-out` directory.

To install the library and tools in a toolchain prefix, like OpenOrbis, run:

```sh
zig build install -p /path/to/OpenOrbis-Toolchain --release=fast
```

Note that you may pick a different release type if you wish (such as `--release=safe`).

## Using as a Zig Build package

Run in your Zig project:
```sh
zig fetch --save git+https://github.com/lateleite/freegnm.git
```

Then in your `build.zig` file:
```zig
pub fn build(b: *std.Build) void {
    // ...

    // Add a reference to freegnm...
    const dep_orbis = b.dependency("freegnm", .{
        .target = target,
        .optimize = optimize,
        // .pic = true, // you may choose to enable PIC for your target, enabled by default when targetting PS4
    });

    // to use the Zig module
    const mod_gnm = dep_gnm.module("gnm");
    // ...then in your executable or library module
    my_module.addImport("gnm", mod_gnm);

    // to link the library to a C/C++ binary:
    const lib_gnm = dep_orbis.artifact("gnm");
    // ...then in your executable or library
    my_module.linkLibrary(lib_gnm);

    // IMPORTANT!
    // if you're targeting PS4, make sure to link a libc
    // to freegnm!
    const lib_musl = ... // for example, with OpenOrbis' musl
    lib_gnm.linkLibrary(lib_musl);

    // ...
}
```

For code usage examples, see [freegnm-examples](https://github.com/lateleite/freegnm-examples).

## Tool usage

### gcn-dis

To disassemble a file containing GCN instructions:

```sh
gcn-dis ./shader.gcn
```

### gnf-conv

To convert the first texture in a GNF to a bitmap:

```sh
# will output to ./texture.png
gnf-conv -f png ./in_texture.gnf ./texture.png
```

To convert the mip level 3 of the first texture in a GNF to a PNG:

```sh
# will out put to ./third_mip.png
gnf-conv -f png -m 3 ./in_texture.gnf ./third_mip.png
```

To convert the 5th face of the 2nd texture in a GNF:

```sh
# will output to ./tex_face.bmp
gnf-conv -f bmp -id 2 -fi 5 ./in_texture.gnf ./tex_face.bmp
```

To convert all faces and mips in the first texture to a KTX container:

```sh
# will output to ./out_texture.ktx
gnf-conv -f ktx ./in_texture.gnf ./out_texture.ktx
```

### gnf-mk

To create a GNF texture from a PNG bitmap:

```sh
gnf-mk -f png ./input_bitmap.png ./out_texture.gnf
```

### pm4-dis

To disassemble a PM4 packet:

```sh
pm4-dis ./packet.bin
```

### psb-dis

To disassemble and dump information from a PSSL shader binary file:

```sh
psb-dis ./vertex_shader.sb
```

## GNF support status

The GNF tools support the following texture types supported:

- 2D
- Cubemaps

And the following formats are supported:

- RGBA8
- RGBA16
- BC6
- BC7

## Libraries and sources

freegnm embeds the following libraries:

- [bcdec](https://github.com/iOrange/bcdec)
- [stb_image and stb_image_write](https://github.com/nothings/stb)

It also uses and references code from the Mesa driver and AMD's PAL.

## License

This project is licensed under the MIT license.

You may find a contributor list in the `CONTRIBUTORS` file.
