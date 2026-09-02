#Requires -Version 5.1
<#
.SYNOPSIS
    FTJ SSD Controller IP Block — RTL Synthesis & PPA Dashboard

.DESCRIPTION
    Runs Yosys synthesis on the FTJ NVMe/NAND SSD controller RTL using the
    bundled generic_cells.lib Liberty file. Generates a gate-level netlist
    and displays a Power-Performance-Area (PPA) summary dashboard.

    No external PDK, WSL, or Docker installation required.
    Yosys for Windows: https://github.com/YosysHQ/oss-cad-suite-build/releases

.PARAMETER YosysPath
    Path to yosys.exe. Defaults to 'yosys' (must be on system PATH).
    Example: -YosysPath "C:\oss-cad-suite\bin\yosys.exe"

.EXAMPLE
    # Run with yosys in PATH:
    .\scripts\run_synthesis.ps1

.EXAMPLE
    # Run with explicit yosys path:
    .\scripts\run_synthesis.ps1 -YosysPath "C:\oss-cad-suite\bin\yosys.exe"
#>
param(
    [string]$YosysPath = "yosys"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Resolve paths ─────────────────────────────────────────────
$ScriptDir = $PSScriptRoot
$RepoRoot  = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$OutputDir = Join-Path $RepoRoot "scripts\output"
$Report    = Join-Path $OutputDir "synthesis_report.log"
$Netlist   = Join-Path $OutputDir "ftj_top_controller_netlist.v"
$YsScript  = Join-Path $RepoRoot "scripts\synthesize.ys"

$Sep = "━" * 60

# ── Banner ────────────────────────────────────────────────────
Write-Host ""
Write-Host $Sep -ForegroundColor Cyan
Write-Host "  FTJ SSD Controller IP — Yosys RTL Synthesis Pipeline" -ForegroundColor Cyan
Write-Host "  Environment : Native Windows 10/11 (No WSL/Docker)"   -ForegroundColor Cyan  
Write-Host "  Cell Library: scripts/generic_cells.lib (130nm-class)" -ForegroundColor Cyan
Write-Host "  Target      : 100 MHz | AXI4 Burst | 3D NAND + WL"    -ForegroundColor Cyan
Write-Host $Sep -ForegroundColor Cyan

# ── Validate Yosys ───────────────────────────────────────────
try {
    $YosysInfo = & $YosysPath --version 2>&1
    Write-Host "  Yosys Found : $($YosysInfo -join ' ')" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "  [ERROR] Yosys not found at: '$YosysPath'" -ForegroundColor Red
    Write-Host "  Download OSS CAD Suite for Windows:" -ForegroundColor Yellow
    Write-Host "  https://github.com/YosysHQ/oss-cad-suite-build/releases" -ForegroundColor Yellow
    Write-Host "  Then add <install-dir>\bin to your system PATH." -ForegroundColor Yellow
    Write-Host "  Or pass: -YosysPath `"C:\oss-cad-suite\bin\yosys.exe`"" -ForegroundColor Yellow
    exit 1
}

# ── Validate HDL sources exist ───────────────────────────────
$RequiredFiles = @(
    (Join-Path $RepoRoot "hdl\ftj_top_controller.v"),
    (Join-Path $RepoRoot "hdl\ftj_submission_queue.v"),
    (Join-Path $RepoRoot "hdl\nand_flash_model.v"),
    (Join-Path $RepoRoot "scripts\generic_cells.lib"),
    $YsScript
)
foreach ($f in $RequiredFiles) {
    if (-not (Test-Path $f)) {
        Write-Host "  [ERROR] Required file not found: $f" -ForegroundColor Red
        exit 1
    }
}

# ── Create output directory ───────────────────────────────────
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "  Created output directory: $OutputDir" -ForegroundColor Gray
}

# ── Run Yosys synthesis ───────────────────────────────────────
Write-Host ""
Write-Host "  Running Yosys synthesis..." -ForegroundColor Yellow
Write-Host "  Script : scripts/synthesize.ys" -ForegroundColor Gray
Write-Host "  Log    : scripts/output/synthesis_report.log" -ForegroundColor Gray
Write-Host ""

$StartTime = Get-Date
try {
    Push-Location $RepoRoot
    & $YosysPath -l $Report $YsScript
    if ($LASTEXITCODE -ne 0) {
        throw "Yosys exited with code $LASTEXITCODE"
    }
} catch {
    Write-Host ""
    Write-Host "  [SYNTHESIS FAILED] $_" -ForegroundColor Red
    Write-Host "  Check log: $Report" -ForegroundColor Yellow
    exit 1
} finally {
    Pop-Location
}
$ElapsedSec = [math]::Round(((Get-Date) - $StartTime).TotalSeconds, 1)

# ── Parse synthesis report ────────────────────────────────────
$LogContent = Get-Content $Report -Raw -ErrorAction SilentlyContinue

$GateCount = "N/A"
$AreaUm2   = 0.0
$AreaMm2   = "N/A"
$FmaxStr   = "N/A (check log)"
$WireCount = "N/A"

if ($LogContent) {
    # Gate count
    if ($LogContent -match 'Number of cells:\s+(\d+)') {
        $GateCount = $Matches[1]
    }
    # Wire count
    if ($LogContent -match 'Number of wires:\s+(\d+)') {
        $WireCount = $Matches[1]
    }
    # Chip area
    if ($LogContent -match 'Chip area for .*?:\s+([\d.]+)') {
        $AreaUm2 = [double]$Matches[1]
        $AreaMm2 = ($AreaUm2 / 1e6).ToString("F6")
    }
    # Estimate Fmax from ABC delay output
    if ($LogContent -match 'Delay\s*=\s*([\d.]+)\s*ns') {
        $DelayNs = [double]$Matches[1]
        if ($DelayNs -gt 0) {
            $FmaxMHz = [math]::Round(1000.0 / $DelayNs, 1)
            $FmaxStr = "$FmaxMHz MHz  (critical path = $($DelayNs)ns)"
        }
    } elseif ($LogContent -match 'abc.*?delay.*?([\d.]+)') {
        $FmaxStr = "See synthesis_report.log for timing"
    }
}

# ── PPA Dashboard ─────────────────────────────────────────────
Write-Host $Sep -ForegroundColor Green
Write-Host "  ╔══════════════ PPA SUMMARY DASHBOARD ══════════════╗" -ForegroundColor Green
Write-Host $Sep -ForegroundColor Green
Write-Host ("  {0,-35} : {1}" -f "Total Gate Count (Equiv.)", $GateCount)         -ForegroundColor White
Write-Host ("  {0,-35} : {1}" -f "Wire Count", $WireCount)                        -ForegroundColor White
Write-Host ("  {0,-35} : {1} µm²" -f "Physical Area (generic_cells.lib)", $AreaUm2) -ForegroundColor White
Write-Host ("  {0,-35} ≈ {1} mm²" -f "Physical Area", $AreaMm2)                   -ForegroundColor White
Write-Host ("  {0,-35} : {1}" -f "Est. Fmax (ABC timing)", $FmaxStr)              -ForegroundColor White
Write-Host ("  {0,-35} : {1}" -f "Target Clock", "100 MHz (10 ns period)")        -ForegroundColor White  
Write-Host ("  {0,-35} : {1}" -f "Process Node", "Generic 130nm-class")           -ForegroundColor White
Write-Host ("  {0,-35} : {1}" -f "Cell Library", "scripts/generic_cells.lib")     -ForegroundColor White
Write-Host $Sep -ForegroundColor Green
Write-Host ("  Synthesis completed in {0}s" -f $ElapsedSec)                    -ForegroundColor DarkGray
Write-Host "  Gate-level netlist : $Netlist"                                   -ForegroundColor DarkGray
Write-Host "  Full synthesis log : $Report"                                    -ForegroundColor DarkGray
Write-Host $Sep -ForegroundColor Green
Write-Host ""
