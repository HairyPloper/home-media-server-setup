[CmdletBinding()]
param(
    [switch]$Start,
    [switch]$Force,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$composeFile = Join-Path $repoRoot 'docker-compose.yml'
$envFile = Join-Path $repoRoot '.env'

function Read-WithDefault {
    param([string]$Prompt, [string]$Default)

    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }
    return $value.Trim()
}

function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $true)

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $answer = (Read-Host "$Prompt $suffix").Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $Default
    }
    return $answer -in @('y', 'yes')
}

function New-SafePassword {
    param([int]$Length = 32)

    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] $Length
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

function ConvertTo-DotEnvValue {
    param([string]$Value)

    if ($Value -match "[`r`n]") {
        throw 'Environment values cannot contain newlines.'
    }
    return "'" + ($Value -replace "'", "\'") + "'"
}

function Get-EnvValue {
    param([string]$Name, [string]$Default)

    if (-not (Test-Path -LiteralPath $envFile)) {
        return $Default
    }
    $match = Get-Content -LiteralPath $envFile | Where-Object { $_ -match "^$([regex]::Escape($Name))=(.*)$" } | Select-Object -First 1
    if ($null -eq $match) {
        return $Default
    }
    $value = ($match -split '=', 2)[1].Trim()
    if (($value.StartsWith("'") -and $value.EndsWith("'")) -or ($value.StartsWith('"') -and $value.EndsWith('"'))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return $value
}

function Invoke-Compose {
    param([string[]]$ComposeArguments)

    Push-Location $repoRoot
    try {
        & docker compose --env-file $envFile -f $composeFile @ComposeArguments
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host ''
Write-Host 'Home Media Server setup wizard' -ForegroundColor Cyan
Write-Host '--------------------------------'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker was not found. Install Docker Desktop or Docker Engine with Compose v2.'
}
& docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Compose v2 is not available.'
}
& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'The Docker daemon is not running or is not accessible.'
}
if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    Write-Warning 'No NVIDIA tooling was detected. Remove the Jellyfin/Plex GPU reservation blocks before starting on a CPU-only host.'
}

$reuseEnv = $false
if ((Test-Path -LiteralPath $envFile) -and -not $Force) {
    $reuseEnv = $ValidateOnly -or (Read-YesNo 'An existing .env was found. Reuse it?' $true)
}
elseif ($ValidateOnly) {
    throw '-ValidateOnly requires an existing .env file.'
}

$defaultDataRoot = Join-Path (Split-Path -Parent $repoRoot) 'home-media-server-data'
if ($reuseEnv) {
    $serverRoot = Get-EnvValue 'SERVER_ROOT' $defaultDataRoot
    $dataRoot = Get-EnvValue 'DATA_ROOT' $serverRoot
    Write-Host "Using existing private settings from $envFile"
}
else {
    $serverRoot = Read-WithDefault 'Configuration and stack directory' $defaultDataRoot
    $dataRoot = Read-WithDefault 'Media and download data directory' (Join-Path $serverRoot 'data')
    $timezone = Read-WithDefault 'IANA timezone' 'Etc/UTC'
    $puid = Read-WithDefault 'Container PUID' '1000'
    $pgid = Read-WithDefault 'Container PGID' '1000'
    $transmissionUser = Read-WithDefault 'Transmission username' 'media'

    $securePassword = Read-Host 'Transmission password (leave blank to generate one)' -AsSecureString
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try {
        $transmissionPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    if ([string]::IsNullOrWhiteSpace($transmissionPassword)) {
        $transmissionPassword = New-SafePassword
        Write-Host 'Generated a random Transmission password and stored it only in .env.' -ForegroundColor Green
    }

    if (Test-Path -LiteralPath $envFile) {
        $backupPath = "$envFile.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
        Copy-Item -LiteralPath $envFile -Destination $backupPath
        Write-Host "Backed up the previous .env to $backupPath"
    }

    $envLines = @(
        'COMPOSE_PROJECT_NAME=home-media-server'
        "SERVER_ROOT=$(ConvertTo-DotEnvValue ($serverRoot -replace '\\', '/'))"
        "DATA_ROOT=$(ConvertTo-DotEnvValue ($dataRoot -replace '\\', '/'))"
        "PUID=$puid"
        "PGID=$pgid"
        "TZ=$(ConvertTo-DotEnvValue $timezone)"
        "TRANSMISSION_USER=$(ConvertTo-DotEnvValue $transmissionUser)"
        "TRANSMISSION_PASS=$(ConvertTo-DotEnvValue $transmissionPassword)"
    )
    $utf8NoBom = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllLines($envFile, $envLines, $utf8NoBom)
    Write-Host "Created private settings at $envFile" -ForegroundColor Green
}

$configDirectories = @(
    'configs/traefik', 'configs/jackett', 'configs/prowlarr', 'configs/sonarr',
    'configs/radarr', 'configs/lidarr', 'configs/bazarr', 'configs/jellyfin',
    'configs/plex', 'configs/seerr', 'configs/heimdall',
    'configs/transmission', 'watch'
)
foreach ($relativePath in $configDirectories) {
    $target = Join-Path $serverRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path $target -Force | Out-Null
}
$dataDirectories = @(
    'media/movies', 'media/music', 'media/tv',
    'torrents/incomplete', 'torrents/movies', 'torrents/music', 'torrents/tv'
)
foreach ($relativePath in $dataDirectories) {
    $target = Join-Path $dataRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path $target -Force | Out-Null
}
Write-Host "Created configuration directories under $serverRoot" -ForegroundColor Green
Write-Host "Created media and download directories under $dataRoot" -ForegroundColor Green

Invoke-Compose @('config', '--quiet')
Write-Host 'Compose configuration is valid.' -ForegroundColor Green

if ($ValidateOnly) {
    $selection = '1'
}
elseif ($Start) {
    $selection = '3'
}
else {
    Write-Host ''
    Write-Host 'Choose the next action:'
    Write-Host '  1. Finish after validation'
    Write-Host '  2. Pull container images'
    Write-Host '  3. Pull images and start the stack'
    Write-Host '  4. Stop the stack'
    $selection = Read-WithDefault 'Selection' '1'
}

switch ($selection) {
    '1' { Write-Host 'Setup complete. No containers were changed.' }
    '2' {
        Invoke-Compose @('pull')
        Write-Host 'Images downloaded. Run docker compose up -d when ready.' -ForegroundColor Green
    }
    '3' {
        Invoke-Compose @('pull')
        Invoke-Compose @('up', '-d')
        Invoke-Compose @('ps')
    }
    '4' {
        if (Read-YesNo 'Stop all services in this stack?' $false) {
            Invoke-Compose @('down')
        }
    }
    default { throw "Unknown selection: $selection" }
}
