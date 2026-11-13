#!/usr/bin/env python3
"""
build_tables.py - Precomputed Lookup Table Generator for CoCo 3 Plasma Tunnel & Starfield.
Generates assembly include files (.inc) and raw binaries (.bin) for:
1. Quadrant Polar Angle (U) and Depth (V) tables.
2. Pre-combined (U ^ V) texture tables.
3. 256-byte Sine/Cosine tables.
4. 256-byte Reciprocal-Z projection table.
5. 256-byte 6-bit RGB color gradient palette tables (xxRGBrgb format).
"""

import math
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)

def coco_rgb(r, g, b):
    """
    Encode RGB values (0..3 each) into CoCo 3 6-bit RGB format (xxRGBrgb).
    Bit 5: Red MSB (32)
    Bit 4: Green MSB (16)
    Bit 3: Blue MSB (8)
    Bit 2: Red LSB (4)
    Bit 1: Green LSB (2)
    Bit 0: Blue LSB (1)
    """
    r = max(0, min(3, int(r)))
    g = max(0, min(3, int(g)))
    b = max(0, min(3, int(b)))
    
    msb_r = (r >> 1) & 1
    lsb_r = r & 1
    msb_g = (g >> 1) & 1
    lsb_g = g & 1
    msb_b = (b >> 1) & 1
    lsb_b = b & 1
    
    val = (msb_r << 5) | (msb_g << 4) | (msb_b << 3) | (lsb_r << 2) | (lsb_g << 1) | lsb_b
    return val

def generate_palette_tables():
    """
    Generate 512-entry smooth cyclical palette table in CoCo 3 6-bit RGB format.
    (256-entry gradient repeated twice for zero-overhead wrapped indexing).
    """
    table_256 = []
    num_entries = 256
    for i in range(num_entries):
        phase = (i / num_entries) * 2.0 * math.pi
        
        # Smooth sine curves for 0..3 intensity
        r_f = 1.5 + 1.49 * math.sin(phase)
        g_f = 1.5 + 1.49 * math.sin(phase + 2.094) # 120 degrees offset
        b_f = 1.5 + 1.49 * math.sin(phase + 4.188) # 240 degrees offset
        
        table_256.append(coco_rgb(round(r_f), round(g_f), round(b_f)))
    
    # Repeat twice to form 512 bytes
    return table_256 + table_256

def generate_sine_table():
    """
    256-byte signed sine table (-127 to +127).
    """
    table = []
    for i in range(256):
        angle = (i / 256.0) * 2.0 * math.pi
        val = int(round(127.0 * math.sin(angle)))
        if val < -127: val = -127
        if val > 127: val = 127
        # Convert to unsigned 8-bit for byte emission
        table.append(val & 0xFF)
    return table

def generate_recip_z():
    """
    256-byte reciprocal Z table: scale = min(255, int(256 * 40 / Z)).
    """
    table = [255] # Z=0
    for z in range(1, 256):
        val = int(round(256.0 * 28.0 / z))
        if val > 255:
            val = 255
        table.append(val)
    return table

def generate_quadrant_tables(width=40, height=50):
    """
    Generate quadrant lookup tables for top-left quadrant (width x height).
    Center is at (width - 0.5, height - 0.5).
    Pixel aspect ratio is 1.666 (CoCo 3 160x200 4:3 display).
    Center void (r < 2.5) is set to Color 0 (Black abyss).
    Surrounding tunnel uses colors 1..14 for neon plasma cycling.
    """
    u_table = []
    v_table = []
    uv_xor_table = []
    
    cx = width - 0.5
    cy = height - 0.5
    aspect = 1.666 # Horizontal aspect ratio correction for circular tunnel
    
    for y in range(height):
        dy = (cy - y)
        for x in range(width):
            dx = (cx - x) * aspect
            r = math.sqrt(dx * dx + dy * dy)
            if r < 0.5:
                r = 0.5
            
            # Angle: 0..63 in quadrant 0
            angle = math.atan2(dy, dx) # 0 to pi/2
            u = int(round((angle / (math.pi / 2.0)) * 63.0)) & 0xFF
            
            # Depth: proportional to 1/r
            v = int(round(180.0 / r)) & 0xFF
            
            u_table.append(u)
            v_table.append(v)
            
            if r < 2.5:
                # Black center void / vanishing point
                color = 0
            else:
                # 14-color cycling plasma (slots 1..14)
                color = 1 + (((u ^ v) >> 1) % 14)
                
            byte_val = (color << 4) | color
            uv_xor_table.append(byte_val)
            
    return u_table, v_table, uv_xor_table

def write_inc_file(filename, name, data, bytes_per_line=16):
    with open(filename, "w") as f:
        f.write(f"; Precomputed Table: {name}\n")
        f.write(f"; Total bytes: {len(data)}\n")
        f.write(f"{name}:\n")
        for i in range(0, len(data), bytes_per_line):
            chunk = data[i:i+bytes_per_line]
            hex_str = ",".join(f"${b:02X}" for b in chunk)
            f.write(f"        FCB     {hex_str}\n")

def write_bin_file(filename, data):
    with open(filename, "wb") as f:
        f.write(bytes(data))

def main():
    print("Generating lookup tables...")
    
    # 1. Sine table
    sin_table = generate_sine_table()
    sin_inc = os.path.join(PROJECT_DIR, "sin_table.inc")
    write_inc_file(sin_inc, "SinTable", sin_table)
    print(f"Generated {sin_inc} (256 bytes)")
    
    # 2. Reciprocal Z table
    recip_z = generate_recip_z()
    recip_inc = os.path.join(PROJECT_DIR, "recip_z.inc")
    write_inc_file(recip_inc, "RecipZTable", recip_z)
    print(f"Generated {recip_inc} (256 bytes)")
    
    # 2b. Row offset table (200 words: y * 80)
    row_offsets = []
    for y in range(200):
        off = y * 80
        row_offsets.append((off >> 8) & 0xFF)
        row_offsets.append(off & 0xFF)
    row_inc = os.path.join(PROJECT_DIR, "row_offsets.inc")
    write_inc_file(row_inc, "RowOffsetTable", row_offsets)
    print(f"Generated {row_inc} (400 bytes)")
    
    # 3. Palette gradient table
    pal_table = generate_palette_tables()
    pal_inc = os.path.join(PROJECT_DIR, "palette_table.inc")
    write_inc_file(pal_inc, "PaletteGradientTable", pal_table)
    print(f"Generated {pal_inc} (512 bytes)")
    
    # 4. Quadrant tables (40 x 50)
    u_table, v_table, uv_xor = generate_quadrant_tables(40, 50)
    
    uv_bin = os.path.join(PROJECT_DIR, "tunnel_quad.bin")
    write_bin_file(uv_bin, uv_xor)
    print(f"Generated {uv_bin} ({len(uv_xor)} bytes)")
    
    u_bin = os.path.join(PROJECT_DIR, "tunnel_u.bin")
    write_bin_file(u_bin, u_table)
    v_bin = os.path.join(PROJECT_DIR, "tunnel_v.bin")
    write_bin_file(v_bin, v_table)
    print(f"Generated {u_bin} and {v_bin} ({len(u_table)} bytes each)")
    
    # Combined include file
    tables_inc = os.path.join(PROJECT_DIR, "tables.inc")
    with open(tables_inc, "w") as f:
        f.write("; Master Tables Include File for CoCo 3 Plasma Tunnel\n\n")
        f.write('        INCLUDE "sin_table.inc"\n')
        f.write('        INCLUDE "recip_z.inc"\n')
        f.write('        INCLUDE "row_offsets.inc"\n')
        f.write('        INCLUDE "palette_table.inc"\n')
    print(f"Generated {tables_inc}")
    print("All tables successfully generated!")

if __name__ == "__main__":
    main()
