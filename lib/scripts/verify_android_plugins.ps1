$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$registrantPath = Join-Path $projectRoot 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
$manifestPath = Join-Path $projectRoot '.flutter-plugins-dependencies'

# --no-pub 构建前必须完成插件注册文件生成，否则 APK 可编译但启动会卡住。
if (-not (Test-Path -LiteralPath $registrantPath) -or -not (Test-Path -LiteralPath $manifestPath)) {
    throw 'Android 插件注册文件缺失，请先成功执行 flutter pub get；Windows 无符号链接权限时可在该命令期间设置 FLUTTER_WINDOWS=false。'
}
$registrant = Get-Content -Encoding UTF8 -Raw -LiteralPath $registrantPath
$manifest = Get-Content -Encoding UTF8 -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$nativePlugins = @($manifest.plugins.android | Where-Object { $_.native_build })
if ($nativePlugins.Count -eq 0 -or $registrant -notmatch 'public static void registerWith') {
    throw 'Android 插件注册文件为空或无效'
}
foreach ($plugin in $nativePlugins) {
    if (-not $registrant.Contains("Error registering plugin $($plugin.name),")) {
        throw "Android 插件注册文件缺少插件：$($plugin.name)；请重新成功执行 flutter pub get"
    }
}
Write-Host "Android 插件注册校验通过：$($nativePlugins.Count) 个原生插件"
