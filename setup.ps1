# Local AI Hub - Setup para Windows (PowerShell)
# Execucao:  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; .\setup.ps1
$ErrorActionPreference = "Stop"

$PythonVersion = "3.11"
$VenvDir = Join-Path $PSScriptRoot ".venv"
$VenvPy  = Join-Path $VenvDir "Scripts\python.exe"

# Binarios pre-compilados do llama.cpp com suporte a CUDA 13.3 / 12.4
$ReleaseTag = "prism-b10709-9a9394a"
$BaseUrl = "https://github.com/PrismML-Eng/llama.cpp/releases/download/$ReleaseTag"

function Refresh-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $merged  = "$machine;$user;$env:Path"
    $seen = @{}; $unique = @()
    foreach ($p in $merged -split ";") {
        $key = $p.TrimEnd("\").ToLowerInvariant()
        if ($key -and -not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $unique += $p
        }
    }
    $env:Path = $unique -join ";"
}

function Find-CompatiblePython {
    $pyLauncher = Get-Command py -CommandType Application -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        foreach ($minor in @("3.13", "3.12", "3.11", "3.10")) {
            try {
                $out = & $pyLauncher.Source "-$minor" --version 2>&1 | Out-String
                if ($out -match "Python (3\.(?:1[0-3]))\.\d+") {
                    $resolvedExe = (& $pyLauncher.Source "-$minor" -c "import sys; print(sys.executable)" 2>$null | Out-String).Trim()
                    if ($resolvedExe -and (Test-Path $resolvedExe)) {
                        return @{ Version = $Matches[1]; Path = $resolvedExe }
                    }
                }
            } catch {}
        }
    }
    foreach ($name in @("python3", "python")) {
        foreach ($cmd in @(Get-Command $name -All -ErrorAction SilentlyContinue)) {
            if (-not $cmd.Source -or $cmd.Source -like "*\WindowsApps\*") { continue }
            try {
                $out = & $cmd.Source --version 2>&1 | Out-String
                if ($out -match "Python (3\.(?:1[0-3]))\.\d+") {
                    return @{ Version = $Matches[1]; Path = $cmd.Source }
                }
            } catch {}
        }
    }
    return $null
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Instalador do Local AI Hub (OmniCoder & Llama API)     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Python ──
Write-Host "==> Verificando Python ..." -ForegroundColor Cyan
$DetectedPython = Find-CompatiblePython
if (-not $DetectedPython) {
    Write-Host "[ERR] Python 3.10+ nao encontrado. Baixe de https://www.python.org/downloads/" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Python $($DetectedPython.Version) encontrado em $($DetectedPython.Path)" -ForegroundColor Green

# ── 2. uv ──
Write-Host "==> Verificando uv ..." -ForegroundColor Cyan
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "==> Instalando uv ..." -ForegroundColor Cyan
    & $DetectedPython.Path -m pip install uv
    Refresh-SessionPath
}
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "[ERR] Falha ao instalar uv." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] uv pronto." -ForegroundColor Green

# ── 3. Ambiente Virtual (.venv) ──
Write-Host "==> Configurando ambiente virtual ..." -ForegroundColor Cyan
if (-not (Test-Path $VenvPy)) {
    uv venv $VenvDir --python "$($DetectedPython.Path)"
}
uv pip install --python $VenvPy huggingface-hub
Write-Host "[OK] Ambiente virtual e dependencias instaladas." -ForegroundColor Green

# ── 4. Deteccao de GPU (NVIDIA CUDA) ──
Write-Host "==> Detectando GPU ..." -ForegroundColor Cyan
$GpuType = "cpu"
$CudaTag = "13.3"

$nvsmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvsmi) {
    $out = & $nvsmi.Source 2>&1 | Out-String
    if ($out -match 'CUDA (?:UMD )?Version:\s+(\d+)\.(\d+)') {
        $major = [int]$Matches[1]; $minor = [int]$Matches[2]
        if ($major -ge 13) {
            $CudaTag = "13.3"
            $GpuType = "cuda"
        } elseif ($major -ge 12 -and $minor -ge 4) {
            $CudaTag = "12.4"
            $GpuType = "cuda"
        }
    }
}

if ($GpuType -eq "cuda") {
    Write-Host "[OK] GPU NVIDIA detectada (CUDA $CudaTag)" -ForegroundColor Green
} else {
    Write-Host "[WARN] Nenhuma GPU NVIDIA compativel detectada. Usando CPU." -ForegroundColor Yellow
}

# ── 5. Baixar Binarios do llama.cpp ──
Write-Host "==> Baixando binarios otimizados do llama.cpp ..." -ForegroundColor Cyan
$BinDir = Join-Path $PSScriptRoot "bin\$GpuType"
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

function Download-Zip($Url, $DestDir, $CheckFile) {
    if (Test-Path (Join-Path $DestDir $CheckFile)) {
        Write-Host "[OK] $CheckFile ja instalado." -ForegroundColor Green
        return
    }
    Write-Host "    Baixando $Url ..." -ForegroundColor Cyan
    $tmp = [System.IO.Path]::GetTempFileName() + ".zip"
    Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
    Expand-Archive -Path $tmp -DestinationPath $DestDir -Force
    Remove-Item $tmp -Force
    Write-Host "[OK] Instalado em $DestDir" -ForegroundColor Green
}

if ($GpuType -eq "cuda") {
    Download-Zip "$BaseUrl/llama-${ReleaseTag}-bin-win-cuda-${CudaTag}-x64.zip" $BinDir "llama-server.exe"
    Download-Zip "$BaseUrl/cudart-llama-bin-win-cuda-${CudaTag}-x64.zip" $BinDir "cublas64_13.dll"
} else {
    Download-Zip "$BaseUrl/llama-${ReleaseTag}-bin-win-cpu-x64.zip" $BinDir "llama-server.exe"
}

# ── 6. Baixar Modelo Padrao (OmniCoder-2-9B) ──
$ModelDir = Join-Path $PSScriptRoot "models\omnicoder2"
New-Item -ItemType Directory -Path $ModelDir -Force | Out-Null
$ModelFile = Join-Path $ModelDir "OmniCoder-2-9B.Q3_K_M.gguf"

if (Test-Path $ModelFile) {
    Write-Host "[OK] Modelo OmniCoder-2-9B ja presente em models\omnicoder2\" -ForegroundColor Green
} else {
    Write-Host "==> Baixando modelo OmniCoder-2-9B (mradermacher/OmniCoder-2-9B-GGUF) ..." -ForegroundColor Cyan
    $HfCli = Join-Path $VenvDir "Scripts\hf.exe"
    & $HfCli download mradermacher/OmniCoder-2-9B-GGUF OmniCoder-2-9B.Q3_K_M.gguf --local-dir $ModelDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERR] Falha no download do modelo." -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] OmniCoder-2-9B baixado com sucesso!" -ForegroundColor Green
}

# ── 7. Criar Atalho na Area de Trabalho ──
$DesktopScript = Join-Path $PSScriptRoot "scripts\create_shortcut.ps1"
if (Test-Path $DesktopScript) {
    & $DesktopScript
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   Instalacao concluida com sucesso!                      " -ForegroundColor Green
Write-Host "  Para iniciar: De dois cliques no atalho 'Local AI Hub - LEG3NDY'  " -ForegroundColor Cyan
Write-Host "                na Area de Trabalho ou execute: .\iniciar_api.bat   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
