"""保留每个原始配置参数的边界，避免 Windows 项目路径被二次拆分。"""

import ctypes
import os
from pathlib import Path
import shlex
import subprocess
import sys


def windows_short_path(path):
    if os.name != "nt":
        return str(path)
    buffer = ctypes.create_unicode_buffer(32768)
    length = ctypes.windll.kernel32.GetShortPathNameW(
        str(path),
        buffer,
        len(buffer),
    )
    return buffer.value if length else str(path)


root = Path(sys.argv[1])
source = (
    Path(sys.argv[3])
    if len(sys.argv) > 3
    else root / "tmp/mpv-0.42.0-upgrade/ffmpeg"
)
install_prefix = (
    Path(sys.argv[4])
    if len(sys.argv) > 4
    else root / "tmp/mpv-0.42.0-upgrade/prefix"
)
source = source.resolve(strict=True)
install_prefix = install_prefix.resolve(strict=True)
project_prefix = Path(windows_short_path(install_prefix)).as_posix()
root = Path(windows_short_path(root.resolve()))
source = Path(windows_short_path(source))
configuration = sys.argv[2].replace("PROJECT_PREFIX", project_prefix)
abi = os.environ.get("FFMPEG_ANDROID_ABI", "arm64-v8a")
target = "aarch64-linux-android24"
if abi == "armeabi-v7a":
    target = "armv7a-linux-androideabi24"
    configuration = (
        configuration.replace("aarch64-linux-android24", target)
        .replace("--arch=aarch64", "--arch=arm")
        .replace("--cpu=armv8-a", "--cpu=armv7-a")
    )
elif abi != "arm64-v8a":
    raise ValueError(f"不支持的 Android ABI：{abi}")
arguments = shlex.split(configuration)
# Windows 主机辅助程序使用 MSVC；Android 目标链接和汇编仍交给 NDK Clang，
# 否则 msvc 工具链会把目标链接器误设为 compat/windows/mslink。
arguments += [
    "--toolchain=msvc",
    "--host-cc=cl.exe",
    "--host-ld=cl.exe",
    f"--ld={target}-clang",
    f"--as={target}-clang",
]
environment = os.environ.copy()
environment["GIT_CEILING_DIRECTORIES"] = str(source.parent)
visual_studio = subprocess.run(
    ["cmd.exe", "/d", "/s", "/c", str(root / "tools/mpv-0.42.0-upgrade/load_vs_environment.cmd")],
    capture_output=True, text=True, encoding="utf-8", errors="replace", check=True,
)
for line in visual_studio.stdout.splitlines():
    if "=" in line:
        key, value = line.split("=", 1)
        if key.lower() in {"include", "lib", "libpath", "path", "vcinstalldir", "windowssdkdir"}:
            environment[key] = value
environment["PATH"] = (
    str(root / "tmp/mpv-0.42.0-upgrade/bin")
    + ";C:/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin;"
    + environment.get("PATH", "")
)
for stale in ("ffbuild/config.log", "ffbuild/config.mak", "config.h"):
    (source / stale).unlink(missing_ok=True)
subprocess.run(["sh", "./configure", *arguments], cwd=source,
               env=environment, check=True)
