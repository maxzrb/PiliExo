@echo off
setlocal

set "PROJECT_ROOT=%~dp0..\.."
pushd "%PROJECT_ROOT%" || exit /b 1

if not defined FFMPEG_SKIP_CONFIGURE set "FFMPEG_SKIP_CONFIGURE=0"

call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 (
    popd
    exit /b 1
)

set "PATH=C:\Android\Sdk\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin;C:\Android\Sdk\ndk\28.2.13676358\prebuilt\windows-x86_64\bin;%PATH%"
"C:\Program Files\Git\bin\bash.exe" "tools\mpv-0.42.0-upgrade\build_ffmpeg.sh"
set "RESULT=%ERRORLEVEL%"

popd
exit /b %RESULT%
