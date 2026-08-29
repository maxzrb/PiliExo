param(
    [string]$FlutterPath = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$fvmrcPath = Join-Path $projectRoot '.fvmrc'
$lockPath = Join-Path $projectRoot 'pubspec.lock'

if ([string]::IsNullOrWhiteSpace($FlutterPath)) {
    $FlutterPath = (Get-Command flutter -ErrorAction Stop).Source
}

if (-not (Test-Path -LiteralPath $FlutterPath)) {
    throw "Flutter SDK 可执行文件不存在：$FlutterPath"
}

$pubspecFlutter = $null
foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $pubspecPath) {
    if ($line -match '^\s*flutter:\s*["'']?(\d+\.\d+\.\d+)["'']?\s*$') {
        $pubspecFlutter = $matches[1]
        break
    }
}
if ([string]::IsNullOrWhiteSpace($pubspecFlutter)) {
    throw 'pubspec.yaml 未声明精确的 Flutter 版本'
}

$fvmFlutter = (Get-Content -Encoding UTF8 -Raw -LiteralPath $fvmrcPath |
        ConvertFrom-Json).flutter.ToString()
if ($pubspecFlutter -ne $fvmFlutter) {
    throw "pubspec.yaml 与 .fvmrc 的 Flutter 版本不一致：$pubspecFlutter / $fvmFlutter"
}

$lockFlutter = $null
foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $lockPath) {
    if ($line -match '^\s*flutter:\s*["'']?(\d+\.\d+\.\d+)["'']?\s*$') {
        $lockFlutter = $matches[1]
        break
    }
}
if ($lockFlutter -ne $pubspecFlutter) {
    throw "pubspec.lock 与项目声明的 Flutter 版本不一致：$lockFlutter / $pubspecFlutter；请用正确 SDK 执行 flutter pub get"
}

$versionOutput = & $FlutterPath --version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "无法执行 Flutter：$FlutterPath`n$($versionOutput -join [Environment]::NewLine)"
}
$versionLine = $versionOutput |
    Where-Object { $_ -match '^Flutter\s+\d+\.\d+\.\d+' } |
    Select-Object -First 1
if ($versionLine -notmatch '^Flutter\s+(\d+\.\d+\.\d+)') {
    throw "无法从 Flutter 输出识别版本：$($versionOutput -join [Environment]::NewLine)"
}
$installedFlutter = $matches[1]

if ($installedFlutter -ne $pubspecFlutter) {
    throw "Flutter SDK 版本不匹配：项目要求 $pubspecFlutter，当前为 $installedFlutter（$FlutterPath）"
}

Write-Host "Flutter 工具链校验通过：$installedFlutter"
Write-Host "Flutter SDK：$FlutterPath"
