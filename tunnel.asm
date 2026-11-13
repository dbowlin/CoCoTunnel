; ==============================================================================
; TUNNEL.ASM - CoCo 3 Procedural Starfield & Plasma Tunnel
; Written in 6809 Assembly for Tandy Color Computer 3 (GIME chip)
; 160x200 16-Color Graphics Mode, Double Buffered, 60 FPS
; ==============================================================================

        ORG     $4000
        SETDP   $00

; --- GIME Hardware Registers ---
INIT0           EQU     $FF90   ; Initialization Register 0 (MMU/Vector control)
INIT1           EQU     $FF91   ; Initialization Register 1 (Task/Timer control)
IRQENR          EQU     $FF92   ; IRQ Enable / Status Register (bit 3 = VBORD)
FIRQENR         EQU     $FF93   ; FIRQ Enable / Status Register
VMODE           EQU     $FF98   ; Video Mode Register ($80 = graphics, 60Hz)
VRES            EQU     $FF99   ; Video Resolution ($36 = 200 lines, 80 bytes/row, 16 col)
BRDR            EQU     $FF9A   ; Border Color Register
VOFFMSB         EQU     $FF9D   ; Video Offset MSB
VOFFLSB         EQU     $FF9E   ; Video Offset LSB
PALETTE         EQU     $FFB0   ; Palette Slot 0 ($FFB0-$FFBF)
RAM_MODE        EQU     $FFDF   ; Switch to all-RAM mode
FASTSPD         EQU     $FFD9   ; 1.79 MHz Fast Clock enable

; --- MMU Task 0 Registers ($FFA0-$FFA7) ---
MMU_TASK0_BANK4 EQU     $FFA4   ; Controls CPU $8000-$9FFF window
MMU_TASK0_BANK5 EQU     $FFA5   ; Controls CPU $A000-$BFFF window

; --- Frame Buffer Window Base ---
BUFFER_BASE     EQU     $8000   ; 16 KB window ($8000-$BFFF)

; --- Number of 3D Stars ---
NUM_STARS       EQU     48

; ==============================================================================
; Entry Point
; ==============================================================================
Start:
        ORCC    #$50            ; Disable IRQ and FIRQ interrupts
        LDS     #$3FFF          ; Set safe stack pointer in Bank 1
        STA     FASTSPD         ; Switch CPU to 1.79 MHz High-Speed Mode
        STA     RAM_MODE        ; Switch to all-RAM mode

        ; Initialize GIME video mode
        LDA     #$40            ; Enable MMU
        STA     INIT0
        LDA     #$80            ; Graphics mode, 60 Hz NTSC
        STA     VMODE
        LDA     #$36            ; 200 scanlines, 80 bytes/row, 16 colors (160x200x16)
        STA     VRES
        LDA     #$00            ; Black border
        STA     BRDR
        LDA     #$08            ; Enable VBORD (vertical border) IRQ latch
        STA     IRQENR

        ; Initialize direct page variables
        CLR     ActiveBuffer
        CLR     PalettePhase
        CLR     TunnelFrame
        LDD     #$ACE1          ; Initial LFSR random seed
        STD     LFSR_Seed

        ; Install FIRQ Interrupt Vector for Scanline Palette Cycling
        LDD     #FIRQ_Handler
        STD     $FFF6           ; Hardware FIRQ vector in all-RAM mode

        ; Enable FIRQ on Horizontal Sync (Bit 4 of $FF93 = HBORD)
        LDA     #$10
        STA     FIRQENR

        ; Enable FIRQ interrupts on 6809 (unmask F bit, keep IRQ masked)
        ANDCC   #$BF

        ; Initialize Base Palette:
        ; Color 0 = Black ($00), Color 15 = Pure White ($3F) for stars
        JSR     InitPalettes

        ; Initialize Both Frame Buffers with Symmetrical Tunnel Texture
        ; 1. Map Buffer A (Blocks 0 & 1 into $8000-$BFFF)
        LDA     #$00
        STA     MMU_TASK0_BANK4
        LDA     #$01
        STA     MMU_TASK0_BANK5
        JSR     RenderTunnelQuadrant

        ; 2. Map Buffer B (Blocks 2 & 3 into $8000-$BFFF)
        LDA     #$02
        STA     MMU_TASK0_BANK4
        LDA     #$03
        STA     MMU_TASK0_BANK5
        JSR     RenderTunnelQuadrant

        ; Initialize 3D Starfield Structures
        JSR     InitStars

        ; Set initial display to Buffer A (Physical Address $00000 / 8 = $0000)
        LDA     #$00
        STA     VOFFMSB
        STA     VOFFLSB

        ; Set active write window to Buffer B (Blocks 2 & 3)
        LDA     #$02
        STA     MMU_TASK0_BANK4
        LDA     #$03
        STA     MMU_TASK0_BANK5
        LDA     #$01
        STA     ActiveBuffer

; ==============================================================================
; Main Animation Loop (Synchronized to 60 FPS V-Sync)
; ==============================================================================
MainLoop:
        ; 1. Wait for Vertical Blanking (VBORD in $FF92)
WaitVBL:
        LDA     IRQENR          ; Read IRQ status (also clears pending flags)
        BITA    #$08            ; Bit 3 = VBORD
        BEQ     WaitVBL

        ; 2. Flip Display Buffers on V-Sync
        LDA     ActiveBuffer
        BEQ     ShowBufA

ShowBufB:
        ; Currently wrote to Buffer B ($04000 physical / 8 = $0800)
        ; Display Buffer B:
        LDA     #$08
        STA     VOFFMSB
        LDA     #$00
        STA     VOFFLSB
        ; Set next write window to Buffer A ($FFA4=$00, $FFA5=$01)
        LDA     #$00
        STA     MMU_TASK0_BANK4
        LDA     #$01
        STA     MMU_TASK0_BANK5
        CLR     ActiveBuffer
        BRA     DoneFlip

ShowBufA:
        ; Currently wrote to Buffer A ($00000 physical / 8 = $0000)
        ; Display Buffer A:
        LDA     #$00
        STA     VOFFMSB
        STA     VOFFLSB
        ; Set next write window to Buffer B ($FFA4=$02, $FFA5=$03)
        LDA     #$02
        STA     MMU_TASK0_BANK4
        LDA     #$03
        STA     MMU_TASK0_BANK5
        LDA     #$01
        STA     ActiveBuffer

DoneFlip:
        ; Reset scanline palette pointer to current frame phase for top of screen
        CLRA
        LDB     PalettePhase
        LDX     #PaletteGradientTable
        LEAX    D,X
        STX     ScanlineColorPtr

        ; 3. Cycle Dynamic Palette for Swirling Tunnel Plasma
        JSR     UpdateDynamicPalette

        ; 4. Erase previous star positions from write buffer
        JSR     EraseStars

        ; 5. Update 3D Star positions, project & draw in back buffer
        JSR     UpdateAndDrawStars

        ; 6. Loop indefinitely
        BRA     MainLoop

; ==============================================================================
; Palette Subroutines
; ==============================================================================
InitPalettes:
        ; Color 0 = True Black ($00)
        CLR     PALETTE
        ; Color 15 = Pure White ($3F)
        LDA     #$3F
        STA     PALETTE+15

        ; Set initial colors 1..14 from PaletteGradientTable
        LDX     #PaletteGradientTable
        LDY     #PALETTE+1
        LDB     #14
InitPalLoop:
        LDA     ,X+
        STA     ,Y+
        DECB
        BNE     InitPalLoop
        RTS

UpdateDynamicPalette:
        ; Increment palette phase each frame
        INC     PalettePhase
        CLRA
        LDB     PalettePhase
        LDX     #PaletteGradientTable
        LEAX    D,X             ; X points to current phase in 512-byte table

        ; Distribute 14 dynamic color slots across gradient
        LDY     #PALETTE+1
        LDB     #14
PalLoop:
        LDA     ,X
        LEAX    17,X            ; Step through gradient
        STA     ,Y+
        DECB
        BNE     PalLoop
        RTS

; ==============================================================================
; Ultra-Fast Scanline FIRQ Handler (Horizontal Border Sync)
; Modulates plasma accent colors per scanline from precomputed gradient
; ==============================================================================
FIRQ_Handler:
        LDA     FIRQENR         ; Acknowledge FIRQ by reading $FF93
        LDX     ScanlineColorPtr
        LDA     ,X+
        STA     PALETTE+3       ; Update plasma accent 1
        STA     PALETTE+7       ; Update plasma accent 2
        STX     ScanlineColorPtr
        RTI

; ==============================================================================
; Symmetrical Tunnel Quadrant Renderer
; Blits 40x50 quadrant table into all 4 quadrants (fills 160x200 = 16,000 bytes)
; ==============================================================================
RenderTunnelQuadrant:
        LDX     #TunnelQuadData ; Pointer to 2,000-byte precomputed quadrant
        CLR     QuadY           ; Y from 0 to 49

QuadRowLoop:
        CLR     QuadX           ; X from 0 to 39

QuadColLoop:
        ; Load texture byte for (QuadX, QuadY)
        LDA     ,X+

        ; Compute row offsets using RowOffsetTable (2 bytes per row)
        ; Row 2Y (Top Line 1)
        LDB     QuadY
        LSLB                    ; B = 2Y
        CLRA
        ASLB
        ROLA
        LDY     #RowOffsetTable
        LDD     D,Y             ; D = (2Y) * 80
        STD     TopRow1

        ; Row 2Y+1 (Top Line 2)
        ADDD    #80
        STD     TopRow2

        ; Row 198 - 2Y (Bottom Line 1)
        LDA     #198
        LDB     QuadY
        ASLB                    ; 2Y
        PSHS    B
        SUBA    ,S+             ; A = 198 - 2Y
        TFR     A,B
        CLRA
        ASLB
        ROLA
        LDD     D,Y             ; D = (198 - 2Y) * 80
        STD     BotRow1

        ; Row 199 - 2Y (Bottom Line 2)
        ADDD    #80
        STD     BotRow2

        ; Calculate X offsets:
        ; Left X = QuadX
        ; Right X = 79 - QuadX
        LDB     #79
        SUBB    QuadX
        STB     RightX

        ; --- 1. Write Top-Left (TopRow1 + QuadX, TopRow2 + QuadX) ---
        LDB     QuadX
        CLRA
        ADDD    TopRow1
        ADDD    #BUFFER_BASE
        TFR     D,Y
        LDA     -1,X
        STA     ,Y              ; TopLine 1, Left
        STA     80,Y            ; TopLine 2, Left

        ; --- 2. Write Top-Right (TopRow1 + RightX) ---
        LDB     RightX
        CLRA
        ADDD    TopRow1
        ADDD    #BUFFER_BASE
        TFR     D,Y
        LDA     -1,X
        STA     ,Y              ; TopLine 1, Right
        STA     80,Y            ; TopLine 2, Right

        ; --- 3. Write Bottom-Left (BotRow1 + QuadX) ---
        LDB     QuadX
        CLRA
        ADDD    BotRow1
        ADDD    #BUFFER_BASE
        TFR     D,Y
        LDA     -1,X
        STA     ,Y              ; BotLine 1, Left
        STA     80,Y            ; BotLine 2, Left

        ; --- 4. Write Bottom-Right (BotRow1 + RightX) ---
        LDB     RightX
        CLRA
        ADDD    BotRow1
        ADDD    #BUFFER_BASE
        TFR     D,Y
        LDA     -1,X
        STA     ,Y              ; BotLine 1, Right
        STA     80,Y            ; BotLine 2, Right

        ; Next column
        INC     QuadX
        LDA     QuadX
        CMPA    #40
        LBNE    QuadColLoop

        ; Next row
        INC     QuadY
        LDA     QuadY
        CMPA    #50
        LBNE    QuadRowLoop

        RTS

; ==============================================================================
; 3D Starfield Engine
; ==============================================================================
InitStars:
        LDX     #0
InitStarLoop:
        JSR     NextRandom
        ANDA    #$7F
        SUBA    #64             ; X in -64..+63
        BNE     InitX_Ok
        INCA
InitX_Ok:
        STA     StarX,X

        JSR     NextRandom
        ANDA    #$7F
        SUBA    #64             ; Y in -64..+63
        BNE     InitY_Ok
        INCA
InitY_Ok:
        STA     StarY,X

        JSR     NextRandom
        ORA     #$07            ; Z in 7..255
        STA     StarZ,X

        CLR     StarActiveA,X
        CLR     StarActiveB,X
        LEAX    1,X
        CMPX    #NUM_STARS
        BNE     InitStarLoop
        RTS

; 16-bit Galois LFSR Random Number Generator
NextRandom:
        LSR     LFSR_Seed       ; Shift high byte right, bit 0 into C
        ROR     LFSR_Seed+1     ; Shift low byte right with C, bit 0 into C
        BCC     NoXor
        LDA     LFSR_Seed
        EORA    #$B4
        STA     LFSR_Seed
NoXor:
        LDA     LFSR_Seed
        EORA    LFSR_Seed+1     ; Output pseudo-random byte in A
        RTS

; Erase previous stars from the active write buffer
EraseStars:
        LDX     #0
EraseLoop:
        LDA     ActiveBuffer
        BEQ     EraseBufA

EraseBufB:
        LDA     StarActiveB,X
        BEQ     NextErase
        TFR     X,D
        ASLB
        ROLA
        LDY     #StarOffsetB
        LDD     D,Y             ; D = screen byte offset
        ADDD    #BUFFER_BASE
        TFR     D,Y
        LDA     StarOrigByteB,X
        STA     ,Y
        BRA     NextErase

EraseBufA:
        LDA     StarActiveA,X
        BEQ     NextErase
        TFR     X,D
        ASLB
        ROLA
        LDY     #StarOffsetA
        LDD     D,Y
        ADDD    #BUFFER_BASE
        TFR     D,Y
        LDA     StarOrigByteA,X
        STA     ,Y

NextErase:
        LEAX    1,X
        CMPX    #NUM_STARS
        BNE     EraseLoop
        RTS

; Update Z, Project (X, Y, Z) and plot star
UpdateAndDrawStars:
        LDX     #0
StarDrawLoop:
        ; Move star towards camera: Z = Z - 3
        LDA     StarZ,X
        SUBA    #3
        CMPA    #4
        BHI     Z_Ok

        ; Reseed star at back of tunnel
        JSR     NextRandom
        ANDA    #$7F
        SUBA    #64
        BNE     ReseedX_Ok
        INCA
ReseedX_Ok:
        STA     StarX,X
        JSR     NextRandom
        ANDA    #$7F
        SUBA    #64
        BNE     ReseedY_Ok
        INCA
ReseedY_Ok:
        STA     StarY,X
        LDA     #250
Z_Ok:
        STA     StarZ,X

        ; Scale = RecipZTable[Z]
        LDB     StarZ,X
        CLRA
        LDY     #RecipZTable
        LDB     D,Y             ; D = 0:Z (unsigned 16-bit offset)
        STB     CurScale

        ; Project ScreenX = 80 + (X * Scale) / 256
        LDA     StarX,X
        BPL     PosX
        NEGA                    ; A = |X|
        LDB     CurScale
        MUL                     ; A = high byte of |X| * Scale
        NEGA
        ADDA    #80
        BRA     DoneX
PosX:
        LDB     CurScale
        MUL                     ; A = high byte of X * Scale
        ADDA    #80
DoneX:
        STA     ScreenX

        ; Check horizontal clipping: 0 <= ScreenX < 160
        CMPA    #160
        LBHS    ClipStar

        ; Project ScreenY = 100 + (Y * Scale) / 256
        LDA     StarY,X
        BPL     PosY
        NEGA
        LDB     CurScale
        MUL
        NEGA
        ADDA    #100
        BRA     DoneY
PosY:
        LDB     CurScale
        MUL
        ADDA    #100
DoneY:
        STA     ScreenY

        ; Check vertical clipping: 0 <= ScreenY < 200
        CMPA    #200
        LBHS    ClipStar

        ; Calculate Byte Offset = ScreenY * 80 + (ScreenX >> 1)
        LDB     ScreenY
        CLRA
        ASLB
        ROLA
        LDY     #RowOffsetTable
        LDD     D,Y             ; D = ScreenY * 80
        STD     TempOffset

        LDB     ScreenX
        LSRB                    ; ScreenX / 2
        CLRA
        ADDD    TempOffset
        STD     CurOffset       ; Current star byte offset

        ; Save background byte and store offset
        ADDD    #BUFFER_BASE
        TFR     D,Y
        LDA     ,Y              ; Read current background byte
        STA     OrigByte

        LDA     ActiveBuffer
        BEQ     SaveBufA

SaveBufB:
        TFR     X,D
        ASLB
        ROLA
        LDY     #StarOffsetB
        LDD     CurOffset
        STD     D,Y
        LDA     OrigByte
        STA     StarOrigByteB,X
        BRA     PlotStar

SaveBufA:
        TFR     X,D
        ASLB
        ROLA
        LDY     #StarOffsetA
        LDD     CurOffset
        STD     D,Y
        LDA     OrigByte
        STA     StarOrigByteA,X

PlotStar:
        ; Plot bright white star pixel (nibble = 15 = $F)
        LDD     CurOffset
        ADDD    #BUFFER_BASE
        TFR     D,Y
        LDA     OrigByte
        LDB     ScreenX
        ANDB    #$01
        BNE     RightPixel

LeftPixel:
        ; Left nibble: (Byte & $0F) | $F0
        ANDA    #$0F
        ORA     #$F0
        STA     ,Y
        BRA     StarPlotted

RightPixel:
        ; Right nibble: (Byte & $F0) | $0F
        ANDA    #$F0
        ORA     #$0F
        STA     ,Y

StarPlotted:
        LDA     ActiveBuffer
        BEQ     PlottedA
PlottedB:
        LDA     #1
        STA     StarActiveB,X
        BRA     NextStar
PlottedA:
        LDA     #1
        STA     StarActiveA,X
        BRA     NextStar

ClipStar:
        LDA     ActiveBuffer
        BEQ     ClipA
ClipB:
        CLR     StarActiveB,X
        BRA     NextStar
ClipA:
        CLR     StarActiveA,X

NextStar:
        LEAX    1,X
        CMPX    #NUM_STARS
        LBNE    StarDrawLoop
        RTS

; ==============================================================================
; Variables & Working Storage
; ==============================================================================
ActiveBuffer:   FCB     0       ; 0 = Buffer A displayed, 1 = Buffer B displayed
PalettePhase:   FCB     0       ; Rotating phase for plasma palette cycling
ScanlineColorPtr: FDB   0       ; Scanline FIRQ gradient pointer
TunnelFrame:    FCB     0
PalCount:       FCB     0
LFSR_Seed:      FDB     $ACE1

QuadX:          FCB     0
QuadY:          FCB     0
TopRow1:        FDB     0
TopRow2:        FDB     0
BotRow1:        FDB     0
BotRow2:        FDB     0
RightX:         FCB     0

CurScale:       FCB     0
ScreenX:        FCB     0
ScreenY:        FCB     0
CurOffset:      FDB     0
TempOffset:     FDB     0
OrigByte:       FCB     0

; Starfield Arrays
StarX:          RMB     NUM_STARS
StarY:          RMB     NUM_STARS
StarZ:          RMB     NUM_STARS

StarActiveA:    RMB     NUM_STARS
StarOffsetA:    RMB     NUM_STARS*2
StarOrigByteA:  RMB     NUM_STARS

StarActiveB:    RMB     NUM_STARS
StarOffsetB:    RMB     NUM_STARS*2
StarOrigByteB:  RMB     NUM_STARS

; ==============================================================================
; Included Data & Precomputed Tables
; ==============================================================================
        INCLUDE "tables.inc"

TunnelQuadData:
        INCLUDEBIN "tunnel_quad.bin"

        END     Start
