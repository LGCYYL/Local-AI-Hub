$desktop = [Environment]::GetFolderPath('Desktop')
$ws = New-Object -ComObject WScript.Shell

# Atalho unico para Iniciar
$startShortcut = Join-Path $desktop "Local AI Hub - LEG3NDY.lnk"
$s = $ws.CreateShortcut($startShortcut)
$s.TargetPath = Join-Path $PSScriptRoot "..\iniciar_api.bat"
$s.WorkingDirectory = Join-Path $PSScriptRoot ".."
$s.Description = "Iniciar Local AI Hub - LEG3NDY"
$s.IconLocation = "powershell.exe,0"
$s.Save()

# Limpa atalhos antigos ou redundantes se existirem
foreach ($old in @("Local AI API.lnk", "Bonsai 27B API.lnk", "Parar Local AI Hub.lnk")) {
    $p = Join-Path $desktop $old
    if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
}

Write-Host "[OK] Atalho criado com sucesso em: $startShortcut" -ForegroundColor Green
