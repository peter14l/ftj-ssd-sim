# PowerShell build script for FTJ Memory Engine Simulator on Windows

param(
    [switch]$RunTests = $true,
    [switch]$RunBenchmarks = $false
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Building FTJ Memory Engine Simulator   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Search for CMake
$cmakePath = Get-Command cmake -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
if (-not $cmakePath) {
    # Check common and Visual Studio / Android SDK installation locations
    $searchPaths = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "C:\Program Files\CMake\bin\cmake.exe",
        "C:\Program Files (x86)\CMake\bin\cmake.exe",
        "C:\AndroidSdk\cmake\3.22.1\bin\cmake.exe",
        "$env:LOCALAPPDATA\Android\Sdk\cmake\3.22.1\bin\cmake.exe"
    )
    
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $cmakePath = $path
            break
        }
    }
}

if (-not $cmakePath) {
    Write-Host "[Error] CMake was not found. Please install CMake or add it to PATH." -ForegroundColor Red
    Exit 1
}

Write-Host "[Info] Using CMake: $cmakePath" -ForegroundColor Green

# 2. Check for Visual Studio environment / generators
$generator = ""
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -property installationPath
    if ($vsPath) {
        Write-Host "[Info] Visual Studio found at: $vsPath" -ForegroundColor Gray
    }
}

# 3. Configure CMake
Write-Host "[Info] Configuring project..." -ForegroundColor Gray
& "$cmakePath" -B build -S .

# 4. Compile targets
Write-Host "[Info] Building targets in Release mode..." -ForegroundColor Gray
& "$cmakePath" --build build --config Release

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       Build Completed Successfully!      " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan

# 5. Run Unit Tests & Physics Verification
if ($RunTests) {
    Write-Host "`n==========================================" -ForegroundColor Yellow
    Write-Host "         Running FTJ Unit Tests          " -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    
    $testExe = "build/Release/ftj_tests.exe"
    if (-not (Test-Path $testExe)) {
        $testExe = "build/ftj_tests.exe"
    }
    
    if (Test-Path $testExe) {
        & "$testExe"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[Error] Unit tests failed with exit code $LASTEXITCODE" -ForegroundColor Red
            Exit $LASTEXITCODE
        }
    } else {
        Write-Host "[Warning] Could not locate ftj_tests.exe at $testExe" -ForegroundColor Yellow
    }
}

# 6. Run CLI Benchmark & Telemetry Suite if requested
if ($RunBenchmarks) {
    Write-Host "`n==========================================" -ForegroundColor Magenta
    Write-Host "       Running FTJ Benchmark Suite        " -ForegroundColor Magenta
    Write-Host "==========================================" -ForegroundColor Magenta
    
    $cliExe = "build/Release/ftj_sim_cli.exe"
    if (-not (Test-Path $cliExe)) {
        $cliExe = "build/ftj_sim_cli.exe"
    }
    
    if (Test-Path $cliExe) {
        & "$cliExe"
    }
}

Write-Host "`nAll operations completed successfully." -ForegroundColor Green
