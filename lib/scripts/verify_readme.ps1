param(
    [string]$ReadmePath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ([string]::IsNullOrWhiteSpace($ReadmePath)) {
    $ReadmePath = Join-Path $projectRoot 'README.md'
}
$readme = Get-Content -Encoding UTF8 -Raw -LiteralPath $ReadmePath
$pubspec = Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
$fvm = Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $projectRoot '.fvmrc') | ConvertFrom-Json

# 只校验 PiliExo 简介，避免原项目 README 快照中的信息影响发布检查。
$intro = ($readme -split '(?m)^## 以下为原项目', 2)[0]
if ($pubspec -notmatch '(?m)^version:\s*(\d{2}\.\d{1,2}\.\d{1,2})\+(\d+)\s*$') {
    throw 'pubspec.yaml 发布版本格式无效'
}
$releaseTag = "v$($matches[1]).$($matches[2])"
if ($intro -notmatch '(?m)^- 当前正式版本：.*?(v\d{2}\.\d{1,2}\.\d{1,2}\.\d+)') {
    throw 'README 缺少当前正式版本，请按发布流程更新项目状态'
}
if ($matches[1] -ne $releaseTag) {
    throw "README 版本过期：$($matches[1])；项目版本：$releaseTag"
}
if ($intro -notmatch '(?m)^- Flutter 工具链：`(\d+\.\d+\.\d+)`') {
    throw 'README 缺少 Flutter 工具链版本，请按发布流程更新项目状态'
}
if ($matches[1] -ne $fvm.flutter) {
    throw "README Flutter 版本过期：$($matches[1])；项目版本：$($fvm.flutter)"
}
if (-not $intro.Contains("https://github.com/maxzrb/PiliExo/releases/tag/$releaseTag)")) {
    throw "README 当前版本下载链接未指向 $releaseTag"
}
Write-Host "README 发布信息校验通过：$releaseTag / Flutter $($fvm.flutter)"
