@echo off
title FTJ & HyperRAM Master Runner
echo ========================================================================
echo          RUNNING ALL SIMULATIONS, TESTS, AND BENCHMARKS
echo ========================================================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0run_all.ps1"

echo.
echo Press any key to open the visual verification report...
pause >nul
start "" "%~dp0hyper_ram\docs\verification_report.html"
