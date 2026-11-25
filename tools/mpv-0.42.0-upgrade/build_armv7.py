"""独立构建 Android ARMv7 的播放器依赖与 libmpv。"""

import argparse
from pathlib import Path
import ctypes
import os
import runpy
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

root = Path(__file__).resolve().parent
repo = root.parents[1]
sources = root / "sources"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("stage", choices=("dependencies", "mpv"))
parser.add_argument("--work", type=Path, required=True, help="项目 tmp 内的 ARMv7 工作目录")
args = parser.parse_args()
work = args.work.resolve()
project_tmp = (repo / "tmp").resolve()
if work == project_tmp or not work.is_relative_to(project_tmp):
    parser.error("工作目录必须位于项目 tmp 内")
prefix = work / "prefix"
prefix.mkdir(parents=True, exist_ok=True)
(prefix / "lib/pkgconfig").mkdir(exist_ok=True, parents=True)
ndk = Path("C:/Android/Sdk/ndk/28.2.13676358")
llvm = ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin"
jobs = min(os.cpu_count() or 8, 10)

def short(path):
    buf = ctypes.create_unicode_buffer(32768)
    return Path(buf.value).as_posix() if ctypes.windll.kernel32.GetShortPathNameW(str(path), buf, len(buf)) else Path(path).as_posix()

env = os.environ.copy()
env.update(PYTHONPATH=str(root / "build-tools"), PKG_CONFIG_SYSROOT_DIR=short(prefix), PKG_CONFIG_LIBDIR=short(prefix / "lib/pkgconfig"))
env.pop("DESTDIR", None)
vs = subprocess.check_output(["cmd.exe", "/d", "/c", str(root / "load_vs_environment.cmd")], text=True, encoding="utf-8", errors="replace")
for line in vs.splitlines():
    key, _, value = line.partition("=")
    if key.upper() in {"INCLUDE", "LIB", "LIBPATH", "PATH", "VCINSTALLDIR", "WINDOWSSDKDIR"}:
        env[key.upper()] = value
env["PATH"] = str(llvm) + ";" + env["PATH"]
# 检测并编译 FriBidi 的 Windows 主机生成器时需要 strings.h 兼容头。
host_headers = work / "windows-headers"
host_headers.mkdir(exist_ok=True)
(host_headers / "strings.h").write_text("#pragma once\n#include <string.h>\n", encoding="ascii")
host = work / "windows-native.ini"
host.write_text((root / "windows-native.ini").read_text(encoding="utf-8").replace(
    "c_args = ['/nologo']", "c_args = ['/nologo', '/I" + host_headers.as_posix() + "']"),
    encoding="utf-8")
cross = work / "android-armv7.ini"
cross.write_text((root / "android-arm64.ini").read_text(encoding="utf-8")
    .replace("aarch64-linux-android24", "armv7a-linux-androideabi24")
    .replace("cpu_family = 'aarch64'", "cpu_family = 'arm'")
    .replace("cpu = 'aarch64'", "cpu = 'armv7a'"), encoding="utf-8")

def run(log, *cmd, run_env=env):
    print("RUN", *map(str, cmd), flush=True)
    with (work / f"{log}.log").open("a", encoding="utf-8") as f:
        subprocess.run(list(map(str,cmd)), cwd=work, env=run_env, stdout=f, stderr=subprocess.STDOUT, check=True)

def cmake(name, source, flags):
    b = work / name
    if not (b / "build.ninja").exists():
        run(name, "cmake", "-S", sources/source, "-B", b, "-G", "Ninja",
            "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_TOOLCHAIN_FILE=" + str(ndk / "build/cmake/android.toolchain.cmake"),
            "-DANDROID_ABI=armeabi-v7a", "-DANDROID_PLATFORM=android-24",
            "-DCMAKE_INSTALL_PREFIX=" + short(prefix),
            "-DBUILD_SHARED_LIBS=OFF", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON", *flags)
    run(name, "cmake", "--build", b, "--target", "install", "--parallel", jobs)

def meson(name, source, flags, target="install"):
    b = work / name
    if not (b / "build.ninja").exists():
        run(name, sys.executable, "-m", "mesonbuild.mesonmain", "setup", b, sources/source,
            "--cross-file", cross, "--native-file", host, "--buildtype", "release",
            "--prefix", "/", "--libdir", "lib", *flags)
    run(name, "ninja", "-C", b, "-j", jobs, target, run_env=env | {"DESTDIR": short(prefix)})

def freetype():
    cmake("freetype","freetype-VER-2-14-3",[f"-DFT_DISABLE_{x}=ON" for x in ("ZLIB","BZIP2","PNG","HARFBUZZ","BROTLI")])

def webp():
    cmake("libwebp","libwebp-1.6.0",[f"-DWEBP_BUILD_{x}=OFF" for x in
        ("ANIM_UTILS","CWEBP","DWEBP","GIF2WEBP","IMG2WEBP","VWEBP","WEBPINFO","WEBPMUX","EXTRAS")])

def mbedtls():
    cmake("mbedtls","mbedtls-3.6.5",["-DENABLE_PROGRAMS=OFF","-DENABLE_TESTING=OFF",
        "-DUSE_STATIC_MBEDTLS_LIBRARY=ON","-DUSE_SHARED_MBEDTLS_LIBRARY=OFF"])

def dav1d():
    meson("dav1d","dav1d-1.5.4",["-Denable_tools=false","-Denable_tests=false","-Denable_examples=false"])

def harfbuzz():
    meson("harfbuzz","harfbuzz-14.3.1",[f"-D{x}=disabled" for x in
        ("glib","gobject","cairo","icu","graphite","graphite2","freetype","tests","docs","utilities","benchmark","subset","raster","vector","gpu")])

def fribidi():
    meson("fribidi","fribidi-1.0.16",["-Dbin=false","-Dtests=false","-Ddocs=false"])

def deps():
    with ThreadPoolExecutor(max_workers=3) as runner:
        futures = [runner.submit(task) for task in (freetype, webp, mbedtls, dav1d, harfbuzz, fribidi)]
        for future in futures:
            future.result()

def output_dependencies():
    with ThreadPoolExecutor(max_workers=2) as pool:
        ass = pool.submit(meson, "libass", "libass-0.17.5", [
            "-Dfontconfig=disabled", "-Ddirectwrite=disabled", "-Dcoretext=disabled",
            "-Drequire-system-font-provider=false", "-Dasm=disabled", "-Dtest=disabled",
            "-Dcompare=disabled", "-Dprofile=disabled", "-Dfuzz=disabled",
            "-Dcheckasm=disabled", "-Ddefault_library=static",
        ])
        placebo = pool.submit(meson, "libplacebo", "libplacebo-7.387.0", [
            "-Ddemos=false", "-Dtests=false", "-Dvulkan=disabled", "-Dvk-proc-addr=disabled",
            "-Dopengl=enabled", "-Dgl-proc-addr=enabled", "-Dd3d11=disabled",
            "-Dglslang=disabled", "-Dshaderc=disabled", "-Dlcms=disabled",
            "-Dlibdovi=disabled", "-Dunwind=disabled", "-Dxxhash=disabled",
            "-Ddefault_library=static",
        ])
        ass.result()
        placebo.result()


def build_mpv():
    ffmpeg_source = Path(
        os.environ.get("FFMPEG_SOURCE_DIR", work / "ffmpeg")
    ).resolve()
    mpv_source = Path(
        os.environ.get("MPV_SOURCE_DIR", sources / "mpv-0.42.0")
    ).resolve()
    output = work / "mpv"
    if not (prefix / "lib/libavcodec.a").is_file():
        raise RuntimeError("先构建并安装 ARMv7 FFmpeg")
    os.environ.update(
        MPV_BUILD_PREFIX=str(prefix),
        FFMPEG_SOURCE_DIR=str(ffmpeg_source),
        MPV_SOURCE_DIR=str(mpv_source),
        MPV_BUILD_DIR=str(output),
    )
    helpers = runpy.run_path(str(root / "build_arm64.py"))
    helpers["generate_ffmpeg_pc"]()
    pc = prefix / "lib/pkgconfig/libplacebo.pc"
    if "-lc++_static" not in pc.read_text(encoding="utf-8"):
        helpers["prepare_libplacebo_pc"]()

    if not (output / "build.ninja").exists():
        run("mpv-setup", sys.executable, "-m", "mesonbuild.mesonmain",
            "setup", output, mpv_source, "--cross-file", cross,
            "--buildtype=release", "-Dprefix=/", "-Dlibmpv=true", "-Dcplayer=false",
            "-Dgpl=false", "-Dlua=disabled", "-Djavascript=disabled", "-Dvulkan=disabled",
            "-Dmanpage-build=disabled", "-Dhtml-build=disabled", "-Dpdf-build=disabled",
            "-Dtests=false", "-Ddefault_library=shared",
            "-Dc_link_args=-Wl,--no-undefined -Wl,-z,max-page-size=16384",
            "-Dcpp_link_args=-Wl,--no-undefined -Wl,-z,max-page-size=16384")
    helpers["remove_host_rpath"](output)
    run("mpv-link", "ninja", "-C", output, "-j", jobs, "libmpv.so")


if args.stage == "dependencies":
    deps()
    output_dependencies()
else:
    build_mpv()
