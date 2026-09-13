@echo off
title Git Push - HyperRAM & FTJ IP
echo ========================================================================
echo           Pushing All Changes to Remote Git Repository
echo ========================================================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0push_changes.ps1"

echo.
pause
