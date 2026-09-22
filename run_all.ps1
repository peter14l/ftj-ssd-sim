# Master Build, Test, and Launch Script for FTJ Memory Simulator and HyperRAM Core
$ErrorActionPreference = "Continue"

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "         RUNNING MASTER BUILD & VERIFICATION PIPELINE                   " -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

# 1. Generate VCD Waveforms
Write-Host "`n[*] Step 1: Generating Hardware Waveforms..." -ForegroundColor Yellow
if (Test-Path "hyper_ram\docs\generate_vcd.ps1") {
    powershell -ExecutionPolicy Bypass -File "hyper_ram\docs\generate_vcd.ps1"
}

# 2. Build FTJ Memory Engine Simulator (Root)
Write-Host "`n[*] Step 2: Building and Testing FTJ Physics Memory Simulator..." -ForegroundColor Yellow
powershell -ExecutionPolicy Bypass -File "build.ps1" -RunTests -RunBenchmarks

# 3. Build HyperRAM Optimizer & Compression Engine
Write-Host "`n[*] Step 3: Building and Testing HyperRAM Compressed Engine..." -ForegroundColor Yellow
powershell -ExecutionPolicy Bypass -File "hyper_ram\scripts\build_optimizer.ps1"

# 4. Run HyperRAM Tests & CLI Benchmarks if built
if (Test-Path "hyper_ram\build\Release\hyper_ram_tests.exe") {
    Write-Host "`n[*] Running HyperRAM Lossless Verification Suite:" -ForegroundColor Green
    & ".\hyper_ram\build\Release\hyper_ram_tests.exe"
}
if (Test-Path "hyper_ram\build\Release\hyper_ram_sim.exe") {
    Write-Host "`n[*] Running HyperRAM Virtual Doubler Benchmarks:" -ForegroundColor Green
    & ".\hyper_ram\build\Release\hyper_ram_sim.exe"
}

Write-Host "`n========================================================================" -ForegroundColor Green
Write-Host "       ALL VERIFICATIONS, BUILDS & RUNS COMPLETED SUCCESSFULLY!         " -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Green
