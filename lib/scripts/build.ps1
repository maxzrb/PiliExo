param(
    [string]$Arg = ''
)

try {
    $versionName = $null
    $versionCode = $null

    $commitHash = (git rev-parse HEAD).Trim()

    $updatedContent = foreach ($line in (Get-Content -Path 'pubspec.yaml' -Encoding UTF8)) {
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

    $updatedContent | Set-Content -Path 'pubspec.yaml' -Encoding UTF8

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
