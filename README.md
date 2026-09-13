# freegnm

freegnm is a library providing GPU accelerated graphics and compute in PlayStation 4's GNM, along with functionality to manage its resources.

Its goal is to provide an equivalent API as close as possible to the official GNM library, with fixes and improvements in its way.

You may find some examples in [freegnm-examples](https://github.com/lateleite/freegnm-examples).

Do know that this library is a work in progress and incomplete, so its **API may change** as it gets developed to completion.

**NOTE:** this hasn't been tested under a Pro/NEO model PlayStation 4.

It also features the following tools:

- gcn-dis - a GCN shader code disassembler
- gnf-conv - a GNF texture to BMP/PNG/KTX converter
- gnf-info - displays information about a GNF texture
- gnf-mk - a GNF texture creator
- pm4-dis - a PM4 packet disassembler
- psb-dis - a PSSL shader binary file disassembler and information dumper

## GNF support

The GNF tools support the following texture types supported:

- 2D
- Cubemaps

And the following formats are supported:

- RGBA8
- RGBA16
- BC6
- BC7

## Tool usage examples

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

## Building

You need the following to build the tools and library:
- A C11 compiler
- GNU Make

To build and install the library to an OpenOrbis prefix, you may:

```sh
export OO_PS4_TOOLCHAIN=/path/to/openorbis
cp config.orbis.mak config.mak
make
make install DESTDIR=$OO_PS4_TOOLCHAIN
```

## Libraries and sources

freegnm embeds the following libraries:

- [bcdec](https://github.com/iOrange/bcdec)
- [stb_image and stb_image_write](https://github.com/nothings/stb)

It also uses code from Mesa and AMD's PAL, including AddrLib and PM4 definitions.

## License

This project is licensed under the MIT license, see [COPYING](COPYING) for more information.
