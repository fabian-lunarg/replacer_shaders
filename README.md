# replacer shaders

Compute shaders for remapping Vulkan resources during capture/replay, used by
[GFXReconstruct](https://github.com/lunarg/gfxreconstruct). This repo exists to give
the shaders their own home and make them easier to iterate on outside of the larger project.

## What they do

Three compute shaders, each dispatched at replay time to fix up resource handles that
differ between the original capture and the replay environment:

**`replacer_bda`** — remaps buffer device addresses. Walks an array of pointers, looks
each captured address up in a sorted range map via binary search, and writes the
corresponding replay-time address. A hashmap blacklist prevents double-replacement if
the same location gets visited more than once.

**`replacer_sbt`** — remaps shader group handles inside a shader binding table. Captures
store opaque 32-byte handles that are driver-specific; this shader translates them to
the replay driver's equivalent using a hashmap lookup.

**`replacer_rehash`** — utility shader that migrates all entries from one hashmap into a
larger one. Used when the blacklist or handle map needs to grow between dispatches.

## Two flavours

The shaders exist in two forms:

- **GLSL** (`.comp` files) — what GFXReconstruct currently uses in production. Targets
  `#version 460` with `GL_EXT_buffer_reference2`, `GL_EXT_scalar_block_layout`,
  `GL_EXT_shader_explicit_arithmetic_types_int64`, and `GL_EXT_shader_atomic_int64`.

- **Slang** (`.slang` files) — a port of the same logic using
  [Slang](https://github.com/shader-slang/slang). Cleaner generics, interface-based
  hashmap (`hashmap_t<K, V>` / `mutable_hashmap_t<K, V>`), and proper module separation.
  Not yet wired into GFXReconstruct.

## Hashmap

Both flavours use the same open-addressing linear-probe hashmap with lock-free atomic
insertion (`atomicCompSwap` / `InterlockedCompareExchange`). Keys and values are either
`uint64_t` device addresses or 32-byte `shader_group_handle_t` structs. Hashing is
xxHash32 (scalar variant from
[Jarzynski & Olano 2020](https://jcgt.org/published/0009/03/02/)).
