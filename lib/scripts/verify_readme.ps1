param(
    [string]$ReadmePath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ([string]::IsNullOrWhiteSpace($ReadmePath)) {
    $ReadmePath = Join-Path $projectRoot 'README.md'
}
$readme = Get-Content -Encoding UTF8 -Raw -LiteralPath $ReadmePath
$fvm = Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $projectRoot '.fvmrc') | ConvertFrom-Json

# 只校验 PiliExo 简介，避免原项目 README 快照中的信息影响发布检查。
$intro = ($readme -split '(?m)^## 以下为原项目', 2)[0]
if ($intro -notmatch 'img\.shields\.io/github/v/release/maxzrb/PiliExo') {
    throw 'README 缺少自动跟进 Release 的版本标签'
}
if (-not $intro.Contains('https://github.com/maxzrb/PiliExo/releases/latest')) {
    throw 'README 缺少最新 Release 链接'
}
if ($intro -notmatch '(?m)^- Flutter 工具链：`(\d+\.\d+\.\d+)`') {
    throw 'README 缺少 Flutter 工具链版本，请按发布流程更新项目状态'
}
if ($matches[1] -ne $fvm.flutter) {
    throw "README Flutter 版本过期：$($matches[1])；项目版本：$($fvm.flutter)"
}
Write-Host "README 发布信息校验通过：自动 Release 标签 / Flutter $($fvm.flutter)"
