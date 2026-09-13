Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "           Pushing All Changes to Remote Git Repository                 " -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

git status

Write-Host "`n[*] Staging all files..." -ForegroundColor Yellow
git add -A

Write-Host "[*] Committing changes with IP protection & 24x7 runtime..." -ForegroundColor Yellow
git commit -m "feat(hyper_ram): 24x7 background engine, VCD waveform logging, proprietary license, and anti-swap benchmarks"

Write-Host "[*] Pushing to remote..." -ForegroundColor Yellow
git push

Write-Host "`n========================================================================" -ForegroundColor Green
Write-Host "                    GIT PUSH COMPLETED                                  " -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Green
