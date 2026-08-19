# One-click restart of the local AI voice server (new version: returns MP3).
# Usage: right-click -> Run with PowerShell
$ErrorActionPreference = "SilentlyContinue"
Set-Location $PSScriptRoot

Write-Host "[1/3] Killing old processes on port 17820 ..."
Get-NetTCPConnection -LocalPort 17820 -State Listen | ForEach-Object {
    Write-Host ("   kill PID " + $_.OwningProcess)
    Stop-Process -Id $_.OwningProcess -Force
}
Start-Sleep -Seconds 1

Write-Host "[2/3] Starting new voice server ..."
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = "python" }
Start-Process -FilePath $py -ArgumentList "tools\tts_server.py --port 17820" -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
Start-Sleep -Seconds 4

Write-Host "[3/3] Verifying server version:"
$ok = $false
try {
    $v = Invoke-RestMethod -Uri "http://127.0.0.1:17820/version" -TimeoutSec 5
    Write-Host ("   " + ($v | ConvertTo-Json -Compress))
    $ok = $true
} catch {
    Write-Host ("   failed: " + $_.Exception.Message)
}
if ($ok) {
    Write-Host "New server is up. Close the game completely, reopen it, then refresh voices."
} else {
    Write-Host "Startup failed. Run manually: python tools\tts_server.py --port 17820"
}
