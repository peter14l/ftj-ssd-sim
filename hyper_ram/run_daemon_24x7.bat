@echo off
title HyperRAM 24x7 Real-Time Background Memory Daemon
echo ======================================================================
echo   Starting HyperRAM 24x7 Real-Time Zero-Swap Engine
echo   Target: Windows 11 on 4GB / 8GB Low-RAM PCs
echo ======================================================================
echo.

if exist "%~dp0HyperRAM_Optimizer.exe" (
    "%~dp0HyperRAM_Optimizer.exe" %*
) else if exist "%~dp0build\Release\HyperRAM_Optimizer.exe" (
    "%~dp0build\Release\HyperRAM_Optimizer.exe" %*
) else (
    echo [!] Executable not found. Please compile first by running:
    echo     powershell -ExecutionPolicy Bypass -File "%~dp0build_optimizer.ps1"
    echo.
    pause
)
