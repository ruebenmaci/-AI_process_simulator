param(
    [switch]$Run,
    [switch]$Clean,
    [ValidateSet("debug","release")]
    [string]$Config = "debug"
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$buildDir = Join-Path $projectRoot "out\build\$Config"
$exePath = Join-Path $buildDir "appChatGPT5_ADT.exe"
$presetName = if ($Config -eq "debug") { "Debug-x64" } else { "Release-x64" }

Write-Host ""
Write-Host "=== rebuild.ps1 (config: $Config) ===" -ForegroundColor Cyan

$running = Get-Process -Name "appChatGPT5_ADT" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "[1] Killing running app..." -ForegroundColor Yellow
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 500
} else {
    Write-Host "[1] No running instance" -ForegroundColor Green
}

if ($Clean) {
    Write-Host "[2] Clean build - deleting build folder" -ForegroundColor Yellow
    if (Test-Path $buildDir) {
        Remove-Item -Recurse -Force $buildDir
    }
} else {
    Write-Host "[2] Incremental build" -ForegroundColor Green
}

Write-Host "[3] Touching qml timestamps" -ForegroundColor Green
$now = Get-Date
$qmlFiles = @()
$qmlRoot = Join-Path $projectRoot "qml"
$cppRoot = Join-Path $projectRoot "cpp"
if (Test-Path $qmlRoot) {
    $qmlFiles += Get-ChildItem -Path $qmlRoot -Recurse -Filter "*.qml"
}
if (Test-Path $cppRoot) {
    $qmlFiles += Get-ChildItem -Path $cppRoot -Recurse -Filter "*.qml"
}
foreach ($f in $qmlFiles) {
    $f.LastWriteTime = $now
}
$qmlCount = $qmlFiles.Count
Write-Host "    Touched $qmlCount files"

Write-Host "[4] Building (preset: $presetName)" -ForegroundColor Green
$buildStart = Get-Date

if (-not (Test-Path $buildDir)) {
    Write-Host "    Build dir missing - running configure first" -ForegroundColor Yellow
    cmake --preset $presetName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "CONFIGURE FAILED" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

cmake --build $buildDir --target appChatGPT5_ADT
$buildDuration = (Get-Date) - $buildStart

if ($LASTEXITCODE -ne 0) {
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "[5] Verifying" -ForegroundColor Green
if (-not (Test-Path $exePath)) {
    Write-Host "Exe missing at: $exePath" -ForegroundColor Red
    exit 1
}

$exeTime = (Get-Item $exePath).LastWriteTime
$newestQml = $qmlFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$newestTime = $newestQml.LastWriteTime

Write-Host "    Newest qml: $newestTime"
Write-Host "    Exe time:   $exeTime"

if ($exeTime -lt $newestTime) {
    Write-Host "STALE BUILD - try -Clean" -ForegroundColor Red
    exit 1
}

$elapsed = [int]$buildDuration.TotalSeconds
Write-Host ""
Write-Host "BUILD OK" -ForegroundColor Green
Write-Host "Elapsed seconds: $elapsed"
Write-Host "Exe: $exePath"

if ($Run) {
    Write-Host ""
    Write-Host "Launching" -ForegroundColor Cyan
    $env:QT_ASSUME_STDERR_HAS_CONSOLE = "1"
    & $exePath
}