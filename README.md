# CPU vs AI

The AI chip on your motherboard lost control! the code it's generating is full of bugs!
Place and upgrade your CPUs to destroy these bugs!
Don't let the bugs get across the PCIE lanes and corrupt your RAM!

TODO: insert image here

TODO: insert video link here

## Installation

TODO: add wasm build?

Clone the repository

```
git clone https://github.com/The-Memory-Managers/cpu-vs-ai
cd hackathon
```

Install zig release version 0.14 and run:

```
zig build run
```

If you are on NixOS, run `nix develop` and then inside it run `zig build run`

## How to play

Left click to place a CPU where a socket is available.

CPUs get upgraded based on how many bugs they destroyed.

An upgraded CPU will show a popup:

- Left click to upgrade bus width (more damage)
- Right click to upgrade cache size (further range)

The amount of CPU cores determine how many bugs it can attack in parallel.

### Tips if you struggle beating a level (spoiler)

- Try positioning your CPUs differently, where they can control the most lanes
- Try experimenting with different bus widths and cache sizes
- If you still can't beat a level, you can skip it by pressing the "s" key
