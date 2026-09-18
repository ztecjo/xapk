# ============================================================================
#  ZTEC XAPK Installer — extract helper
#  Copyright (c) 2026 ZTEC JO
#  Licensed under the MIT License. See LICENSE for details.
#
#  Supported platform: Windows only (Windows 10 / 11).
#  Extracts an .xapk (ZIP-based) package to a destination folder.
#  Called by install.bat — not intended as a standalone customer tool.
# ============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'

# Windows-only guard (reject non-Windows hosts / unusual runtimes).
if ($env:OS -ne 'Windows_NT' -or
    [System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    Write-Host '[ERROR] This helper supports Windows only.'
    exit 1
}

function Write-Step([string]$Message) {
    Write-Host "        $Message"
}

function Test-HasApk([string]$Path) {
    return [bool](Get-ChildItem -LiteralPath $Path -Filter '*.apk' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Clear-Destination([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    Write-Host "[ERROR] Source package not found: $Source"
    exit 1
}

Clear-Destination -Path $Destination

$ok = $false
$zipCopy = $null

# Expand-Archive only accepts .zip — XAPK is the same format with another extension.
try {
    Write-Step "Unpacking package..."
    $zipCopy = Join-Path $env:TEMP ("ztec_xapk_" + [guid]::NewGuid().ToString('N') + '.zip')
    Copy-Item -LiteralPath $Source -Destination $zipCopy -Force
    Expand-Archive -LiteralPath $zipCopy -DestinationPath $Destination -Force
    if (Test-HasApk -Path $Destination) {
        $ok = $true
    }
} catch {
    # Fall through to tar / 7-Zip.
}

if (-not $ok) {
    Clear-Destination -Path $Destination
    Write-Step "Retrying with tar..."
    & tar -xf $Source -C $Destination 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-HasApk -Path $Destination)) {
        $ok = $true
    }
}

if (-not $ok) {
    Clear-Destination -Path $Destination
    Write-Step "Retrying with 7-Zip..."
    $sevenZip = $null
    foreach ($candidate in @(
            "${env:ProgramFiles}\7-Zip\7z.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
        )) {
        if (Test-Path -LiteralPath $candidate) {
            $sevenZip = $candidate
            break
        }
    }
    if (-not $sevenZip) {
        $cmd = Get-Command 7z -ErrorAction SilentlyContinue
        if ($cmd) { $sevenZip = $cmd.Source }
    }

    if ($sevenZip) {
        & $sevenZip x -y $Source "-o$Destination" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-HasApk -Path $Destination)) {
            $ok = $true
        }
    }
}

if ($zipCopy -and (Test-Path -LiteralPath $zipCopy)) {
    Remove-Item -LiteralPath $zipCopy -Force -ErrorAction SilentlyContinue
}

if ($ok) {
    exit 0
}

Write-Host "[ERROR] Unable to extract package."
exit 1
