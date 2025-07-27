# CPU vs AI

The AI chip on your motherboard lost control! the code it's generating is full of bugs!
Place and upgrade your CPUs to destroy these bugs!
Don't let the bugs get across the PCIE lanes and corrupt your RAM!

TODO: insert image here

## Installation

TODO: add wasm build?

Clone the repository

```
git clone https://github.com/The-Memory-Managers/hackathon
cd hackathon
```

Depending on your computer, run the following:

- Linux (wayland, x86_64) - `./bin/linux-x86_64-wayland`
- Linux (x11, x86_64) - `./bin/linux-x86_64-x11`
- MacOS - `./bin/mac-arm`
- Windows (win 10/11, x86_64) - `./bin/win-x86_64.exe`

## Build from source

Install zig release version 0.14 run:

```
zig build run
```

If you are on NixOS, run `nix develop` and then inside it run `zig build run`
