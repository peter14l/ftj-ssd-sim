# Run HyperRAM in Silent Background Mode 24x7
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = "$scriptDir\HyperRAM_Optimizer.exe"
if (-not (Test-Path $exe)) {
    $exe = "$scriptDir\build\Release\HyperRAM_Optimizer.exe"
}

if (Test-Path $exe) {
    Start-Process -FilePath $exe -WindowStyle Hidden
    Write-Host "[+] HyperRAM is now running silently in the background 24x7!" -ForegroundColor Green
    Write-Host "[i] It will monitor memory every 2s and auto-prevent swap freezing." -ForegroundColor Yellow
} else {
    Write-Host "[-] Executable not found. Please compile first." -ForegroundColor Red
}
