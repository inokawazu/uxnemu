# Zig for UXN

This repo contains tooling for the virtual machine, UXN, by `Devine Lu Linvega`.
Please check out his page at [uxn.html](https://wiki.xxiivv.com/site/uxn.html).
My goal of this project was to explore Zig with a non-trivial project and to make an 
extenable UXN toolchain and emulator base.

- `zig build` to build the project (from the project's root directory.)
    - Outputs `uxncli` and `uxnasm`.
- `zig run_asm -- <input.tal> <output.rom>` to run the assembler or you can use `uxnasm`.
- `zig run_cli -- <rom> [cli-args...]` to run the cli supported emulator (no file support so far) or you can use `uxncli`.
