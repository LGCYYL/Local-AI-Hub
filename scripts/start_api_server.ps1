# Local AI API Server (Headless, OpenAI-compatible, Ultra-low memory)
# Usage: .\scripts\start_api_server.ps1
$ErrorActionPreference = "Stop"

$DemoDir = Split-Path $PSScriptRoot -Parent
Set-Location $DemoDir

$Bin = Join-Path $DemoDir "bin\cuda\llama-server.exe"
if (-not (Test-Path $Bin)) {
    Write-Host "[ERR] llama-server.exe nao encontrado em bin\cuda. Execute .\setup.ps1 primeiro." -ForegroundColor Red
    exit 1
}

# Encerra qualquer instancia anterior orfa do llama-server para evitar conflito de porta
$existing = Get-Process llama-server -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[INFO] Encerrando instancia anterior do llama-server..." -ForegroundColor Yellow
    Stop-Process -Name llama-server -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600
}

# Configura Job Object do Windows para garantir encerramento automatico pelo kernel
# caso a janela seja fechada no [X], Ctrl+C ou encerramento do processo.
Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class ProcessJobTracker {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll")]
    private static extern bool SetInformationJobObject(IntPtr hJob, int infoType, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public Int64 PerProcessUserTimeLimit;
        public Int64 PerJobUserTimeLimit;
        public UInt32 LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public UInt32 ActiveProcessLimit;
        public UIntPtr Affinity;
        public UInt32 PriorityClass;
        public UInt32 SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IO_COUNTERS {
        public UInt64 ReadOperationCount;
        public UInt64 WriteOperationCount;
        public UInt64 OtherOperationCount;
        public UInt64 ReadTransferCount;
        public UInt64 WriteTransferCount;
        public UInt64 OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryLimit;
        public UIntPtr PeakJobMemoryLimit;
    }

    private static IntPtr _jobHandle = IntPtr.Zero;

    public static void Init() {
        if (_jobHandle == IntPtr.Zero) {
            _jobHandle = CreateJobObject(IntPtr.Zero, null);
            var info = new JOBOBJECT_BASIC_LIMIT_INFORMATION {
                LimitFlags = 0x2000 // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            };
            var extendedInfo = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
                BasicLimitInformation = info
            };
            int length = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
            IntPtr extendedInfoPtr = Marshal.AllocHGlobal(length);
            try {
                Marshal.StructureToPtr(extendedInfo, extendedInfoPtr, false);
                SetInformationJobObject(_jobHandle, 9, extendedInfoPtr, (uint)length);
            } finally {
                Marshal.FreeHGlobal(extendedInfoPtr);
            }
        }
    }

    public static bool TrackProcess(Process proc) {
        Init();
        if (_jobHandle != IntPtr.Zero && proc != null && !proc.HasExited) {
            return AssignProcessToJobObject(_jobHandle, proc.Handle);
        }
        return false;
    }
}
"@ -ErrorAction SilentlyContinue

function Format-CommandLineArgs([string[]]$Arguments) {
    $escaped = foreach ($arg in $Arguments) {
        if ($arg -match '[\s"]') {
            '"' + ($arg -replace '(\\*)(")', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
        } else {
            $arg
        }
    }
    return ($escaped -join ' ')
}

# Localiza automaticamente o modelo .gguf na pasta models\
$Model = $null
$Alias = "default"

if ($env:MODEL_PATH -and (Test-Path $env:MODEL_PATH)) {
    $Model = $env:MODEL_PATH
} else {
    # Prioriza OmniCoder, ou qualquer modelo GGUF presente
    $omni = Get-ChildItem -Path (Join-Path $DemoDir "models") -Filter "*omnicoder*.gguf" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($omni) {
        $Model = $omni.FullName
        $Alias = "OmniCoder-9B"
    } else {
        $anyGguf = Get-ChildItem -Path (Join-Path $DemoDir "models") -Filter "*.gguf" -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*mmproj*" -and $_.Name -notlike "*dspark*" } |
            Select-Object -First 1
        if ($anyGguf) {
            $Model = $anyGguf.FullName
            $Alias = [System.IO.Path]::GetFileNameWithoutExtension($anyGguf.Name)
        }
    }
}

if (-not $Model) {
    Write-Host "[ERR] Nenhum modelo .gguf encontrado na pasta models\." -ForegroundColor Red
    Write-Host "      Baixe um modelo (ex: OmniCoder) ou execute .\setup.ps1." -ForegroundColor Yellow
    exit 1
}

$Port = if ($env:PORT) { $env:PORT } elseif ($env:BONSAI_PORT) { $env:BONSAI_PORT } else { "8080" }
$HostAddress = if ($env:HOST) { $env:HOST } elseif ($env:BONSAI_HOST) { $env:BONSAI_HOST } else { "127.0.0.1" }
$Ctx = if ($env:CTX) { $env:CTX } elseif ($env:BONSAI_CTX) { $env:BONSAI_CTX } else { "131072" }
$Ngl = if ($env:NGL) { $env:NGL } elseif ($env:BONSAI_NGL) { $env:BONSAI_NGL } else { "99" }

$Np = if ($env:NP) { $env:NP } else { "4" }

# -np 4 --kv-unified: 4 slots simultaneos para suportar sub-agentes com pool unificado dinamico
# KV4: Cache Q4_0 reduz o uso de VRAM em 3.5x permitindo 128k context em GPUs de 8GB
# --no-webui: Desativa a interface web e proxies pesados
$ServerArgs = @(
    "-m", $Model,
    "--alias", "$Alias,default",
    "--host", $HostAddress,
    "--port", "$Port",
    "-ngl", $Ngl,
    "-fa", "on",
    "-c", $Ctx,
    "-np", $Np,
    "--kv-unified",
    "--cache-type-k", "q4_0",
    "--cache-type-v", "q4_0",
    "--no-webui",
    "--jinja",
    "--temp", "0.6",
    "--top-p", "0.95",
    "--top-k", "20",
    "--repeat-penalty", "1.15"
)

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      Local AI API Server (OpenAI Compatible API)         " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Modelo:    $Model" -ForegroundColor Green
Write-Host "  Alias:     $Alias (acessivel tambem como 'default')" -ForegroundColor Green
Write-Host "  GPU:       -ngl $Ngl (100% VRAM na GPU)" -ForegroundColor Green
Write-Host "  Slots:     -np $Np (Pool KV Unificado: suporte a sub-agentes e multi-turnos)" -ForegroundColor Green
Write-Host "  Contexto:  -c $Ctx (128k com Flash Attention e KV Cache 4-bit)" -ForegroundColor Green
Write-Host "  WebUI:     Desativada (--no-webui para maxima performance)" -ForegroundColor Green
Write-Host ""
Write-Host "  Endpoint:  http://${HostAddress}:${Port}/v1/chat/completions" -ForegroundColor Yellow
Write-Host "  Modelos:   http://${HostAddress}:${Port}/v1/models" -ForegroundColor Yellow
Write-Host "  Pressione Ctrl+C ou feche a janela para parar." -ForegroundColor Gray
Write-Host ""

$BinDir = Split-Path $Bin -Parent
$env:Path = "$BinDir;$env:Path"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Bin
$psi.Arguments = Format-CommandLineArgs ($ServerArgs + $args)
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $false

$proc = [System.Diagnostics.Process]::Start($psi)
[ProcessJobTracker]::TrackProcess($proc) | Out-Null

try {
    $proc.WaitForExit()
} finally {
    if ($proc -and -not $proc.HasExited) {
        try { $proc.Kill() } catch {}
    }
    Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "`n[OK] Servidor finalizado e recursos de GPU/VRAM liberados." -ForegroundColor Yellow
}
