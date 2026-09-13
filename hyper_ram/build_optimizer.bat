@echo off
setlocal
echo ======================================================================
echo   Building HyperRAM_Optimizer.exe (Standalone Windows 11 Utility)
echo ======================================================================

REM Find cl.exe from Visual Studio
where cl >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [*] Found MSVC compiler in PATH. Compiling...
    cl /std:c++20 /O2 /EHsc /W3 src\win_optimizer.cpp /Fe:HyperRAM_Optimizer.exe psapi.lib
    goto done
)

REM Fallback to CMake
echo [*] Looking for CMake...
cmake -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target HyperRAM_Optimizer
copy build\Release\HyperRAM_Optimizer.exe . >nul 2>nul

:done
if exist HyperRAM_Optimizer.exe (
    echo.
    echo [SUCCESS] HyperRAM_Optimizer.exe built successfully!
    echo Location: %CD%\HyperRAM_Optimizer.exe
    echo You can now send this single file directly to your friend!
) else (
    echo [!] Build completed in build\Release\HyperRAM_Optimizer.exe
)

echo.
pause
