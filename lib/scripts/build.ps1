param(
    [string]$Arg = ''
)

try {
    $versionName = $null
    $versionCode = $null

    $commitHash = (git rev-parse HEAD).Trim()

    $originalContent = Get-Content -Path 'pubspec.yaml' -Encoding UTF8
    $updatedContent = foreach ($line in $originalContent) {
        if ($line -match '^\s*version:\s*(\d{2}\.\d{1,2}\.\d{1,2})\+(\d+)') {
            $versionName = $matches[1]
            $versionCode = [int]$matches[2]
            "version: $versionName+$versionCode"
        }
        else {
            $line
        }
    }

    if ($null -eq $versionName -or $null -eq $versionCode) {
        throw 'version must use YY.M.D+build format, for example 26.8.28+1'
    }

    $originalText = [string]::Join([Environment]::NewLine, $originalContent)
    $updatedText = [string]::Join([Environment]::NewLine, $updatedContent)
    if ($originalText -ne $updatedText) {
        # 只有版本确实变化时才写回，避免预构建脚本破坏 pubspec 的编码和换行。
        [System.IO.File]::WriteAllText(
            'pubspec.yaml',
            $updatedText,
            [System.Text.UTF8Encoding]::new($false)
        )
    }

    $buildTime = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())

    $data = @{
        'pili.name' = $versionName
        'pili.code' = $versionCode
        'pili.hash' = $commitHash
        'pili.time' = $buildTime
    }

    $data | ConvertTo-Json -Compress | Out-File 'pili_release.json' -Encoding UTF8

    if ($env:GITHUB_ENV) {
        Add-Content -Path $env:GITHUB_ENV -Value "version=$versionName+$versionCode"
    }
}
catch {
    Write-Error "Prebuild Error: $($_.Exception.Message)"
    exit 1
}
