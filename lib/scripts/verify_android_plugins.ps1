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

# stock media_kit 预编译 JAR 会把未打补丁的 libmpv 静默带进 APK。
# 构建前必须拒绝 stock 核心；没有 JAR 副本时要求 jniLibs 提供定制 HDR 核心。
Add-Type -AssemblyName System.IO.Compression.FileSystem
$mediaKit = $manifest.plugins.android |
    Where-Object { $_.name -eq 'media_kit_libs_android_video' } |
    Select-Object -First 1
$jarDir = if ($mediaKit) { Join-Path $mediaKit.path 'android/build' } else { $null }
$jarAbis = @()
$mpvJarFound = $false
if ($jarDir -and (Test-Path -LiteralPath $jarDir)) {
    $jarAbis = Get-ChildItem -LiteralPath $jarDir -Recurse -Filter 'default-*.jar' |
        ForEach-Object { $_.BaseName -replace '^default-', '' } |
        Where-Object { $_ -notmatch 'x86' } |
        Sort-Object -Unique
    Get-ChildItem -LiteralPath $jarDir -Recurse -Filter '*.jar' | ForEach-Object {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($_.FullName)
        try {
            foreach ($entry in $zip.Entries) {
                if ($entry.FullName -notmatch '(^|/)libmpv\.so$') { continue }
                $mpvJarFound = $true
                $memory = [System.IO.MemoryStream]::new()
                $stream = $entry.Open()
                try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
                $text = [Text.Encoding]::ASCII.GetString($memory.ToArray())
                if (-not $text.Contains('android-hdr-signal-passthrough')) {
                    throw "media_kit 预编译 JAR 含 stock libmpv：$($_.FullName)；已禁止打包，请提供定制 HDR 核心。"
                }
            }
        } finally {
            $zip.Dispose()
        }
    }
}
if ($jarAbis.Count -eq 0) {
    $jniRoot = Join-Path $projectRoot 'android/app/src/main/jniLibs'
    if (Test-Path -LiteralPath $jniRoot) {
        $jarAbis = Get-ChildItem -LiteralPath $jniRoot -Directory |
            ForEach-Object { $_.Name } |
            Where-Object { $_ -notmatch 'x86' }
    }
}
if (-not $mpvJarFound) {
    if ($jarAbis.Count -eq 0) {
        throw '无法确定 Android ABI 或未找到已打补丁的 libmpv.so；不能继续打包。'
    }
    $jniRoot = Join-Path $projectRoot 'android/app/src/main/jniLibs'
    foreach ($abi in $jarAbis) {
        $candidate = Join-Path $jniRoot "$abi/libmpv.so"
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "未找到已打补丁的 libmpv.so：$candidate；stock 核心已删除，不能继续打包。"
        }
        $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($candidate))
        if (-not $text.Contains('android-hdr-signal-passthrough')) {
            throw "jniLibs 中的 libmpv.so 不是定制 HDR 核心：$candidate"
        }
    }
}
Write-Host "libmpv HDR 核心校验通过"
Write-Host "Android 插件注册校验通过：$($nativePlugins.Count) 个原生插件"
