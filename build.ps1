# build.ps1 - Automated build and package script for CoCo 3 Plasma Tunnel & Starfield
$ErrorActionPreference = "Stop"

$LWASM = "C:\Users\dave\Code\lwtools-4.25-win64\lwasm.exe"
$DECB = "C:\Users\dave\Code\decb.exe"
$PROJECT_DIR = "C:\Users\dave\Code\CoCoTunnel"

Write-Host "=== 1. Generating Lookup Tables ==="
python "$PROJECT_DIR\tools\build_tables.py"

Write-Host "=== 2. Assembling 6809 Code (lwasm) ==="
& $LWASM --6809 --decb --list="$PROJECT_DIR\tunnel.lst" --output="$PROJECT_DIR\TUNNEL.BIN" "$PROJECT_DIR\tunnel.asm"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Assembly failed!"
    exit 1
}
Write-Host "TUNNEL.BIN created successfully."

Write-Host "=== 3. Creating Floppy Disk Image (tunnel.dsk) ==="
$DSK = "$PROJECT_DIR\tunnel.dsk"
if (Test-Path $DSK) {
    Remove-Item $DSK -Force
}

& $DECB dskini "$DSK"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to format dsk image"
    exit 1
}

Write-Host "=== 4. Adding TUNNEL.BIN to Disk ==="
& $DECB copy -2 -b "$PROJECT_DIR\TUNNEL.BIN" "${DSK},TUNNEL.BIN"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to copy TUNNEL.BIN to disk"
    exit 1
}

Write-Host "=== 5. Creating AUTOEXEC.BAS ==="
# BASIC auto-loader:
# 10 CLEAR 200,&H3FFF
# 20 LOADM "TUNNEL.BIN"
# 30 EXEC
$basContent = "10 CLEAR 200,&H3FFF`r`n20 LOADM`"TUNNEL.BIN`"`r`n30 EXEC`r`n"
Set-Content -Path "$PROJECT_DIR\AUTOEXEC.BAS" -Value $basContent -NoNewline

& $DECB copy -0 -t "$PROJECT_DIR\AUTOEXEC.BAS" "${DSK},AUTOEXEC.BAS"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to copy AUTOEXEC.BAS to disk"
    exit 1
}

Write-Host "=== Build Complete: tunnel.dsk is ready! ==="
