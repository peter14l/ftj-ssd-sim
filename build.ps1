# PowerShell build script for FTJ Memory Engine Simulator on Windows

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Building FTJ Memory Engine Simulator   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Search for CMake
$cmakePath = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmakePath) {
    # Check common installation locations
    $programFiles = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFiles)
    $programFilesX86 = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFilesX86)
    
    $searchPaths = @(
        "$programFiles\CMake\bin\cmake.exe",
        "$programFilesX86\CMake\bin\cmake.exe",
        "C:\Program Files\CMake\bin\cmake.exe"
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

# 2. Check for compilers (MSVC build tools or GCC via MinGW)
$generator = ""
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    Write-Host "[Info] Visual Studio installation found. Using MSVC Toolset." -ForegroundColor Gray
} else {
    # Try MinGW
    $gccPath = Get-Command g++ -ErrorAction SilentlyContinue
    if ($gccPath) {
        Write-Host "[Info] MinGW GCC compiler found." -ForegroundColor Gray
        $generator = '-G "MinGW Makefiles"'
    }
}

# 3. Configure CMake
Write-Host "[Info] Configuring project..." -ForegroundColor Gray
if ($generator -ne "") {
    Invoke-Expression "& `"$cmakePath`" -B build -S . $generator"
} else {
    Invoke-Expression "& `"$cmakePath`" -B build -S ."
}

# 4. Compile targets
Write-Host "[Info] Building targets..." -ForegroundColor Gray
Invoke-Expression "& `"$cmakePath`" --build build --config Release"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       Build Completed Successfully!      " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Executables located under: build/Release/ or build/" -ForegroundColor Gray
