# Local AI CLI Runner (Interactive / Direct CLI Prompting)
# Usage: .\scripts\run_llama.ps1 [-p "Sua pergunta"]
$ErrorActionPreference = "Stop"

$DemoDir = Split-Path $PSScriptRoot -Parent
Set-Location $DemoDir

$BinCandidates = @(
    "bin\cuda\llama-cli.exe",
    "bin\cpu\llama-cli.exe",
    "llama.cpp\build\bin\Release\llama-cli.exe"
)

$BinRel = $null
foreach ($cand in $BinCandidates) {
    if (Test-Path (Join-Path $DemoDir $cand)) { $BinRel = $cand; break }
}

if (-not $BinRel) {
    Write-Host "[ERR] llama-cli.exe nao encontrado. Execute .\setup.ps1 primeiro." -ForegroundColor Red
    exit 1
}

$Bin = Join-Path $DemoDir $BinRel
$BinDir = Split-Path $Bin -Parent
$env:Path = "$BinDir;$env:Path"

# Configura Job Object do Windows para garantir encerramento automatico pelo kernel
Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class ProcessJobTrackerCLI {
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

# Encontra o modelo .gguf na pasta models\
$Model = $null
if ($env:MODEL_PATH -and (Test-Path $env:MODEL_PATH)) {
    $Model = $env:MODEL_PATH
} else {
    $omni = Get-ChildItem -Path (Join-Path $DemoDir "models") -Filter "*omnicoder*.gguf" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($omni) {
        $Model = $omni.FullName
    } else {
        $anyGguf = Get-ChildItem -Path (Join-Path $DemoDir "models") -Filter "*.gguf" -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*mmproj*" -and $_.Name -notlike "*dspark*" } |
            Select-Object -First 1
        if ($anyGguf) {
            $Model = $anyGguf.FullName
        }
    }
}

if (-not $Model) {
    Write-Host "[ERR] Nenhum modelo .gguf encontrado na pasta models\." -ForegroundColor Red
    Write-Host "      Execute .\setup.ps1 ou baixe um modelo .gguf para a pasta models\" -ForegroundColor Yellow
    exit 1
}

$Ngl = if ($env:NGL) { $env:NGL } elseif ($BinRel -like "bin\cpu\*") { "0" } else { "99" }
$Ctx = if ($env:CTX) { $env:CTX } else { "131072" }

$OneShot = if ($args | Where-Object { $_ -in @("-p", "--prompt") }) { @("-st") } else { @() }

$RunArgs = @(
    "-m", $Model,
    "-ngl", $Ngl,
    "-fa", "on",
    "-c", $Ctx,
    "--cache-type-k", "q4_0",
    "--cache-type-v", "q4_0",
    "--temp", "0.6",
    "--top-p", "0.95",
    "--top-k", "20",
    "--repeat-penalty", "1.15"
) + $OneShot

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "           Local AI Hub - CLI Interativo                  " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Modelo:    $Model" -ForegroundColor Green
Write-Host "  GPU:       -ngl $Ngl" -ForegroundColor Green
Write-Host "  Contexto:  -c $Ctx" -ForegroundColor Green
Write-Host ""

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Bin
$psi.Arguments = Format-CommandLineArgs ($RunArgs + $args)
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $false

$proc = [System.Diagnostics.Process]::Start($psi)
[ProcessJobTrackerCLI]::TrackProcess($proc) | Out-Null

try {
    $proc.WaitForExit()
    exit $proc.ExitCode
} finally {
    if ($proc -and -not $proc.HasExited) {
        try { $proc.Kill() } catch {}
    }
    Get-Process llama-cli -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
