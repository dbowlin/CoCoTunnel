# CoCo 3 Procedural Starfield & Plasma Tunnel

A smooth, colorful retro demoscene demonstration for the **Tandy Color Computer 3 (CoCo 3)**.

It features a classic swirling procedural plasma tunnel with continuous neon color-cycling, overlaid with a 3D starfield shooting outward from the center vanishing point. Everything runs natively on the machine at a fluid 60 frames per second with zero external dependencies.

---

## Running the Demo

### On an Emulator (MAME, VCC, or MESS)
1. Mount `tunnel.dsk` into Drive 1.
2. From the Disk Extended Color BASIC prompt, type:
   ```basic
   RUN"AUTOEXEC"
   ```
   *(or `LOADM"TUNNEL.BIN":EXEC`)*

### On Real Hardware
* Write `tunnel.dsk` to a physical 3.5" or 5.25" floppy disk using your preferred disk imaging utility (e.g., DriveWire, CoCo-SDC, or a physical floppy controller), insert into drive 1, and type `RUN"AUTOEXEC"`.

---

## Building from Source

If you want to modify or rebuild the project:

### Prerequisites
* **Python 3** (used to generate the math and lookup tables)
* **`lwasm`** (LWTOOLS 6809 cross-assembler)
* **`decb`** (Toolshed Disk BASIC imaging utility)

### Build Steps
Run the automated PowerShell build script from the project folder:
```powershell
.\build.ps1
```
This generates:
* `TUNNEL.BIN` — Compiled machine-language binary
* `tunnel.dsk` — Bootable floppy disk image

---

## Development Notes

This project was developed with assistance from **Google Gemini** for algorithmic design, 6809 assembly implementation, precomputed math generation, and MAME-assisted emulator testing.

---

## License

This software and source code are released into the **Public Domain**. You are free to use, modify, distribute, or incorporate it into your own creations without restriction.
