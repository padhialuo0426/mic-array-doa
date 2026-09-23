# Build with Vivado/Vitis 2025.2 on Windows. Tool executables may be supplied
# explicitly or resolved from PATH. No SSH host, Git history or lab data needed.
[CmdletBinding()]
param(
    [ValidateSet('all','hw','sw','boot')][string]$Stage = 'all',
    [string]$OutputDir = 'build/latest',
    [string]$Vivado = 'vivado.bat',
    [string]$Vitis = 'vitis.bat',
    [string]$ArmToolchain = '',
    [string]$Bootgen = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$root = Split-Path $PSScriptRoot -Parent
if (![IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path $root $OutputDir }
$out = [IO.Path]::GetFullPath($OutputDir)
if ($Stage -in @('all','sw') -and (Test-Path (Join-Path $out 'vitis'))) {
    throw 'Vitis workspace already exists; choose a fresh -OutputDir.'
}
if ($Stage -in @('all','hw')) { $Vivado = (Get-Command $Vivado -ErrorAction Stop).Source }
if ($Stage -in @('all','sw')) { $Vitis = (Get-Command $Vitis -ErrorAction Stop).Source }
if ($Stage -ne 'hw') {
    if (!$Bootgen) {
        $parentDir = Split-Path $Vitis -Parent
        $sibling = if ($parentDir) { Join-Path $parentDir 'bootgen.bat' } else { '' }
        $Bootgen = if ($sibling -and (Test-Path $sibling)) { $sibling } else { 'bootgen.bat' }
    }
    $Bootgen = (Get-Command $Bootgen -ErrorAction Stop).Source
}
if ($Stage -eq 'sw' -and !(Test-Path (Join-Path $out 'top.xsa'))) {
    throw 'Software build requires top.xsa in -OutputDir; build hardware first.'
}
if ($ArmToolchain) {
    $env:MIC_ARM_TOOLCHAIN = (Resolve-Path $ArmToolchain).Path
}
New-Item -ItemType Directory -Force $out | Out-Null
$env:MIC_BUILD_DIR = $out
$env:PYTHONUNBUFFERED = '1'
$env:NO_PROXY = (@($env:NO_PROXY,'localhost','127.0.0.1','::1') | Where-Object { $_ }) -join ','

function Invoke-BuildTool {
    param([string]$Tool, [string[]]$ToolArgs, [string]$Log)
    # Windows PowerShell 5 treats native stderr as ErrorRecord objects even
    # for warnings. Use the process exit status and success markers instead.
    $ErrorActionPreference = 'Continue'
    & $Tool @ToolArgs 2>&1 | Tee-Object -FilePath $Log | Out-Host
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "Build tool failed with exit code ${code}: $Log" }
}

Push-Location $root
try {
    if ($Stage -in @('all','hw')) {
        $log = Join-Path $out 'vivado-console.log'
        Invoke-BuildTool $Vivado @('-mode','batch','-nojournal','-log',
            (Join-Path $out 'vivado.log'),'-source',(Join-Path $root 'hw/build.tcl')) $log
        if (!(Test-Path (Join-Path $out 'top.xsa')) -or
            !(Test-Path (Join-Path $out 'top.bit')) -or
            !(Select-String -Quiet -Path $log -Pattern '^MIC_HARDWARE_BUILD_OK$')) {
            throw 'Hardware build did not produce validated outputs.'
        }
    }
    if ($Stage -in @('all','sw')) {
        $log = Join-Path $out 'vitis.log'
        Invoke-BuildTool $Vitis @('-s',(Join-Path $root 'sw/build.py')) $log
        foreach ($name in @('app.elf','display.elf','fsbl.elf')) {
            if (!(Test-Path (Join-Path $out $name))) { throw "Missing output: $name" }
        }
        if (!(Select-String -Quiet -Path $log -Pattern '^MIC_SOFTWARE_BUILD_OK$')) {
            throw 'Software build did not pass validation; see vitis.log.'
        }
    }
    if ($Stage -ne 'hw') {
        foreach ($name in @('fsbl.elf','top.bit','app.elf','display.elf','sd_build_validated.txt')) {
            if (!(Test-Path (Join-Path $out $name))) { throw "Missing boot input: $name" }
        }
        Copy-Item (Join-Path $root 'sw/boot.bif') (Join-Path $out 'boot.bif') -Force
        Push-Location $out
        try {
            Invoke-BuildTool $Bootgen @('-arch','zynq','-image','boot.bif','-o','BOOT.BIN','-w','on') (Join-Path $out 'bootgen.log')
            Invoke-BuildTool $Bootgen @('-arch','zynq','-read','BOOT.BIN') (Join-Path $out 'bootgen-read.txt')
            if (!(Test-Path 'BOOT.BIN') -or (Get-Item 'BOOT.BIN').Length -lt 1048576) {
                throw 'BOOT.BIN missing or unexpectedly small.'
            }
            (Get-FileHash 'BOOT.BIN' -Algorithm SHA256).Hash.ToLower() + '  BOOT.BIN' |
                Set-Content -Encoding ASCII 'BOOT.BIN.sha256'
            Write-Host 'MIC_SD_BOOT_IMAGE_OK'
        } finally { Pop-Location }
    }
    Write-Host "Build complete: $out"
} finally {
    Pop-Location
}
