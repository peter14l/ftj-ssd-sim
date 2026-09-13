Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Building HyperRAM_Optimizer.exe (Standalone Windows 11 Utility)" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Check if cl.exe is in path
if (Get-Command "cl.exe" -ErrorAction SilentlyContinue) {
    Write-Host "[*] Compiling with MSVC cl.exe directly..." -ForegroundColor Green
    cl.exe /std:c++20 /O2 /EHsc /W3 src/win_optimizer.cpp /Fe:HyperRAM_Optimizer.exe psapi.lib
} else {
    Write-Host "[*] Configuring and building via CMake..." -ForegroundColor Yellow
    cmake -B build -G "Visual Studio 17 2022" -A x64
    cmake --build build --config Release --target HyperRAM_Optimizer
    if (Test-Path "build\Release\HyperRAM_Optimizer.exe") {
        Copy-Item "build\Release\HyperRAM_Optimizer.exe" "HyperRAM_Optimizer.exe" -Force
    }
}

if (Test-Path "HyperRAM_Optimizer.exe") {
    Write-Host "`n[SUCCESS] HyperRAM_Optimizer.exe has been built!" -ForegroundColor Green
    Write-Host "File Path: $scriptDir\HyperRAM_Optimizer.exe" -ForegroundColor White
    Write-Host "You can directly email, send via WhatsApp, or USB drive this file to your friend!`n" -ForegroundColor Cyan
} else {
    Write-Host "`n[!] Executable located at: $scriptDir\build\Release\HyperRAM_Optimizer.exe" -ForegroundColor Yellow
}
