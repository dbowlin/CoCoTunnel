# LLM Implementation Guide: Tandy CoCo 3 Procedural Starfield & Plasma Tunnel

## 1. Objective & Core Requirements
Build a standalone, auto-booting Tandy Color Computer 3 (CoCo 3) demoscene application written entirely in **6809 assembly** (with optional Hitachi 6309 native-mode optimizations) that renders a **60 FPS Procedural Starfield & Plasma Tunnel** with dynamic scanline color-cycling.

* **Zero External Runtime Dependencies:** No host Python scripts or Becker port streaming at runtime. Everything runs natively on stock CoCo 3 hardware (128K/512K) and emulators (MAME/VCC).
* **Deliverables:**
  1. Well-commented assembly source (`tunnel.asm`) and lookup table generator/data (`tables.inc`).
  2. Compiled Disk BASIC binary (`TUNNEL.BIN`).
  3. Standalone, auto-booting floppy disk image (`tunnel.dsk`).
* **Quality Standards:** Bug-free execution, zero screen tearing, cycle-budgeted for smooth 60 FPS performance, and verified live via the MAME `CoCo3_MCP_Server`.

---

## 2. Toolchain & Environment Setup
* **Assembler:** `lwasm` (from LWTOOLS) using DECB binary output format (`--decb`).
* **Disk Imaging Tool:** `decb` (from Toolshed) to format and populate `.dsk` images.
* **Target Emulator & Debugger:** MAME (`coco3` or `coco3h` driver) controlled via `CoCo3_MCP_Server` for programmatic boot, memory inspection, register verification, breakpoint profiling, and visual frame capture.

---

## 3. CoCo 3 Hardware & Memory Architecture

### A. CPU & Clock Speed
* Disable interrupts immediately on entry (`ORCC #$50`).
* Enable High-Speed Mode (1.79 MHz) by writing to `$FFD9` (`STA $FFD9`).
* Configure GIME Initialization Register 0 (`$FF90`) to enable CoCo 3 GIME features, MMU, and FIRQ/IRQ routing (`$4C` or `$6C` depending on ROM mapping needs; copy any needed vectors or run entirely in RAM with ROMs disabled via `$FFDE`/`$FFDF` all-RAM mode).

### B. Graphics Mode & Double Buffering
* **Resolution:** **160x200, 16-color graphics mode** (2 pixels per byte; 80 bytes per scanline; 16,000 bytes per frame buffer).
* **GIME Registers:**
  * `$FF98` (Video Mode Register): `$80` (Graphics mode).
  * `$FF99` (Video Resolution Register): `$15` (200 lines, 80 bytes/row, 16 colors).
  * `$FF9A` (Border Color): `$00` (Black).
  * `$FF9D` / `$FF9E` (Vertical Offset Register): Points to the active physical 512K/128K RAM page (`physical_address / 8`).
* **MMU Banking (`$FFA0–$FFA7`):**
  * Map two separate 16 KB screen buffers (Buffer A and Buffer B) into the CPU's `$4000–$7FFF` address window during rendering, while the GIME displays the opposite buffer.
  * Swap buffers on V-Sync by updating `$FF9D/$FF9E`—eliminating all flicker and tearing.

### C. Scanline Palette Cycling (H-Sync FIRQ)
* **GIME Palette Registers (`$FFB0–$FFBF`):** 16 hardware color slots (each 6-bit RGB: `xxRGBrgb`).
* **Interrupt Setup:**
  * Configure GIME Initialization Register 1 (`$FF91`) and FIRQ Enable Register (`$FF93`) to trigger an **FIRQ on Horizontal Sync (H-Sync)** (`$01` or `$02` timer/H-sync source).
  * Point the hardware FIRQ vector (`$FFF6/$FFF7` in all-RAM mode, or `$FEF4` via BASIC RAM vector) to a ultra-fast, cycle-counted ISR.
  * On every scanline (or every 2nd scanline to preserve CPU cycles for 3D star math), the FIRQ handler updates a subset or full bank of `$FFB0–$FFBF` from a precomputed smooth color-gradient table, producing hundreds of simultaneous colors on screen.

---

## 4. Algorithmic Design & Optimization Strategy

### A. Precomputed Lookup Tables (Zero Real-Time Trig/Division)
Because the 6809 lacks a hardware divide instruction (and runs at 1.79 MHz), precompute all heavy math into aligned 256-byte lookup tables:
1. **Tunnel UV / Polar Table (`160x100` mirrored to `160x200`):**
   * Because a centered tunnel is radially symmetric across X and Y quadrants, store only the top-left quadrant (`80x100` = 8,000 bytes for Angle `U` and 8,000 bytes for Depth `V`), and mirror horizontally/vertically when blitting. This cuts memory usage by 75% and allows the entire table to fit in two 8 KB MMU blocks.
2. **Sine / Cosine Table (`256` bytes):**
   * Signed 8-bit values (`-127` to `+127`) for smooth tunnel wobble, camera panning, and color-cycle phase offsets.
3. **Reciprocal Z-Projection Table (`256` bytes):**
   * Precomputed `K / Z` scale factors so 3D star projection uses fast 8x8 unsigned `MUL` instructions instead of division.
4. **6-Bit RGB Gradient Palette Table (`256` bytes):**
   * Smoothly transitioning CoCo 3 hardware color codes (`$00–$3F`) arranged so adjacent entries form seamless neon plasma gradients.

### B. Rendering Pipeline (Per Frame at 60 FPS)
1. **Tunnel Background Render (Unrolled Loop):**
   * Advance `time_u` and `time_v` counters each frame.
   * Use `U` (stack pointer) and `X`/`Y` index registers to read `(angle + time_u) ^ (depth + time_v)` from the quadrant tables, pack two 4-bit color indices per byte, and blast bytes into the back buffer.
   * Mirror rows vertically/horizontally to fill all `160x200` pixels in minimal cycles.
2. **3D Starfield Overlay (64–128 Stars):**
   * Each star struct holds: `X` (signed 8-bit), `Y` (signed 8-bit), `Z` (unsigned 8-bit, `1..255`), and `PrevOffset` (16-bit screen offset).
   * Decrement `Z` by star speed. If `Z <= speed`, respawn star at `Z = 255` with pseudo-random `X, Y` (via a 16-bit Galois LFSR).
   * Compute `ScreenX = 80 + (X * RecipZ[Z]) >> 8` and `ScreenY = 100 + (Y * RecipZ[Z]) >> 8`.
   * Clip to `[0..159, 0..199]` and plot bright white/cyan pixels directly over the rendered tunnel in the back buffer (using nibble masking `AND #$F0` / `AND #$0F` so adjacent plasma pixels stay intact).
3. **V-Sync & Buffer Flip:**
   * Wait for V-Sync flag (set by V-Sync IRQ or GIME status read), reset the H-Sync palette table pointer for scanline 0, flip `$FF9D/$FF9E` to the newly rendered buffer, and repeat.

---

## 5. Build & Auto-Boot Disk Packaging
Use the following commands to assemble the binary and build a self-booting `.DSK` image:

```bash
# 1. Assemble the 6809 source into a Disk BASIC binary
lwasm --6809 --decb --list=tunnel.lst --output=TUNNEL.BIN tunnel.asm

# 2. Initialize a clean 35-track CoCo floppy disk image
decb dskini tunnel.dsk

# 3. Copy the compiled machine-language binary onto the disk
decb copy -2 -b TUNNEL.BIN tunnel.dsk,TUNNEL.BIN

# 4. Create an auto-running BASIC loader (or custom boot sector)
printf '10 CLEAR 200,&H3FFF\r20 LOADM"TUNNEL.BIN"\r30 EXEC\r' > autoexec.bas
decb copy -0 -t autoexec.bas tunnel.dsk,AUTOEXEC.BAS
```

*(Note: Alternatively, write a 256-byte boot loader to Track 34, Sector 1 with signature `'OS'` so typing `DOS` from Disk BASIC—or passing `-autoboot_command "DOS\n"` in MAME—boots directly into machine code without touching BASIC RAM.)*

---

## 6. MAME MCP Verification & Debugging Checklist
Once `tunnel.dsk` is built, execute the following test loop using `CoCo3_MCP_Server`:

1. **Boot & Launch:**
   * Start MAME with `coco3`, mount `tunnel.dsk`, and execute `RUN"AUTOEXEC"` (or `DOS`).
2. **Register & Vector Audit:**
   * Inspect `$FF90–$FF9F` to confirm GIME 160x200x16 mode is active and `$FF9D/$FF9E` points to valid RAM pages.
   * Verify FIRQ and IRQ vectors point to valid ISR addresses and stack pointers (`S` and `U`) do not collide with screen buffers or lookup tables.
3. **Cycle Budget & FPS Profiling:**
   * Set breakpoints at the start and end of the main frame loop. Measure elapsed CPU cycles between V-Syncs (target: `< 29,800` cycles per frame at 1.79 MHz for locked 60 FPS; if over budget, switch to every-2nd-scanline H-Sync updates or 2x2 pixel-doubled tunnel blocks).
4. **Visual Verification:**
   * Capture screenshots across multiple consecutive frames to confirm:
     * Smooth, symmetric plasma tunnel animation with no horizontal jitter.
     * Rich multi-gradient scanline colors without palette glitching on the left/right edges.
     * Crisp 3D stars radiating smoothly from the center vanishing point without out-of-bounds memory corruption.