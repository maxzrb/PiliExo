"""续建 mpv 0.42 arm64 候选，保留项目的 FFmpeg 与播放策略补丁。"""

from pathlib import Path
import ctypes
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "build-tools"))


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
SOURCES = ROOT / "sources"
BUILD = ROOT / "build"
TOOLS = ROOT / "build-tools"
PREFIX = Path(os.environ.get("MPV_BUILD_PREFIX", REPO / "tmp/mpv-0.42.0-upgrade/prefix")).resolve()
FFMPEG_SOURCE = Path(os.environ.get("FFMPEG_SOURCE_DIR", REPO / "tmp/mpv-0.42.0-upgrade/ffmpeg")).resolve()
MPV_SOURCE = Path(os.environ.get("MPV_SOURCE_DIR", SOURCES / "mpv-0.42.0")).resolve()
MPV_BUILD_DIR = Path(os.environ.get("MPV_BUILD_DIR", BUILD / "mpv-0.42-arm64")).resolve()
CROSS = ROOT / "android-arm64.ini"
PYTHON = Path(sys.executable)
NDK = Path("C:/Android/Sdk/ndk/28.2.13676358")
LLVM = NDK / "toolchains/llvm/prebuilt/windows-x86_64/bin"


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


ENV = os.environ.copy()
ENV["PYTHONPATH"] = str(TOOLS)
ENV["PKG_CONFIG_LIBDIR"] = windows_short_path(PREFIX / "lib/pkgconfig")
ENV["PKG_CONFIG_SYSROOT_DIR"] = windows_short_path(PREFIX)
ENV["DESTDIR"] = windows_short_path(PREFIX)
ENV["PATH"] = f"{TOOLS / 'bin'};{LLVM};{ENV['PATH']}"


def run(*args, cwd=REPO, env=ENV):
    print("RUN", shlex.join(str(arg) for arg in args), flush=True)
    subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, check=True)


def copy_overwrite(source, destination):
    # 依赖版本变化时同名头文件必须覆盖，否则会复用上一版本。
    target = Path(destination)
    if target.exists():
        mode = target.stat().st_mode
        if not mode & stat.S_IWUSR:
            target.chmod(mode | stat.S_IWUSR)
    return shutil.copy2(source, target)


def make_writable_tree(root):
    # Meson/Ninja 在 Windows 上会把部分中间文件标记为只读。
    for path in [root, *root.rglob("*")]:
        mode = path.stat().st_mode
        if not mode & stat.S_IWUSR:
            path.chmod(mode | stat.S_IWUSR)


def remove_host_rpath(build):
    # Meson 会把 NDK 宿主机系统库目录写入 RUNPATH；Android 包不能携带该路径。
    ninja_file = build / "build.ninja"
    text = ninja_file.read_text(encoding="utf-8")
    updated, count = re.subn(r' "-Wl,-rpath,[^"\r\n]+"', "", text)
    if '"-Wl,-rpath,' in updated:
        raise RuntimeError("Meson 链接参数中仍有未清理的宿主 RPATH")
    if count:
        ninja_file.write_text(updated, encoding="utf-8", newline="")
        print(f"REMOVED_HOST_RPATH={count}", flush=True)


def meson_build(name, options, target="install"):
    build = BUILD / name
    source_name = {
        "libass-arm64": "libass-0.17.5",
        "libplacebo-arm64": "libplacebo-7.387.0",
    }[name]
    if not (build / "build.ninja").exists():
        run(PYTHON, "-m", "mesonbuild.mesonmain", "setup", build, SOURCES / source_name,
            "--cross-file", CROSS, "--buildtype=release", "-Dprefix=/",
            *options)
    make_writable_tree(build)
    run("ninja", "-C", build, target)


def generate_ffmpeg_pc():
    for name in ("libavcodec", "libavformat", "libavutil", "libswscale", "libswresample"):
        version_file = (
            FFMPEG_SOURCE
            / name
            / f"{name}.version"
        )
        version_match = re.search(
            rf"^{name}_VERSION=(.+)$",
            version_file.read_text(encoding="utf-8"),
            re.MULTILINE,
        )
        if not version_match:
            raise RuntimeError(f"无法读取 {name} 的 ABI 版本")
        text = f"""prefix={PREFIX.as_posix()}
exec_prefix=${{prefix}}
libdir=${{prefix}}/lib
includedir=${{prefix}}/include

Name: {name}
Description: FFmpeg {name} for the local Android build
Version: {version_match.group(1).strip()}
Requires:
Requires.private:
Libs: -L${{libdir}} -l{name[3:]} -lm -lz -landroid -llog -lmediandk -lmbedtls -lmbedx509 -lmbedcrypto -ldav1d -lwebp -lwebpmux -lwebpdemux -lsharpyuv
Libs.private:
Cflags: -I${{includedir}}
"""
        (PREFIX / "lib/pkgconfig" / f"{name}.pc").write_text(text, encoding="utf-8")


def prepare_ffmpeg():
    pc = PREFIX / "lib/pkgconfig/libavcodec.pc"
    if (PREFIX / "lib/libavcodec.a").exists() and pc.exists():
        print("PASS 已存在 FFmpeg 静态库，生成 pkg-config 描述", flush=True)
        generate_ffmpeg_pc()
        return
    print("FFmpeg 静态库尚未准备，不能复用其他前缀的未知二进制。", flush=True)
    raise SystemExit(2)


def prepare_libplacebo_pc():
    pc = PREFIX / "lib/pkgconfig/libplacebo.pc"
    text = pc.read_text(encoding="utf-8")
    updated = re.sub(
        r"(?m)^Libs: (.+)$",
        r"Libs: \1 -lc++_static -lc++abi",
        text,
        count=1,
    )
    if updated != text:
        pc.chmod(0o666)
        pc.write_text(updated, encoding="utf-8")


def build_mpv():
    source = MPV_SOURCE
    build = MPV_BUILD_DIR
    if not (build / "build.ninja").exists():
        run(PYTHON, "-m", "mesonbuild.mesonmain", "setup", build, source,
            "--cross-file", CROSS, "--buildtype=release", "-Dprefix=/",
            "-Dlibmpv=true", "-Dcplayer=false", "-Dgpl=false", "-Dlua=disabled",
            "-Djavascript=disabled", "-Dvulkan=disabled", "-Dmanpage-build=disabled",
            "-Dhtml-build=disabled", "-Dpdf-build=disabled", "-Dtests=false",
            "-Ddefault_library=shared", "-Dc_link_args=-Wl,--no-undefined",
            "-Dcpp_link_args=-Wl,--no-undefined")
    make_writable_tree(build)
    remove_host_rpath(build)
    run("ninja", "-C", build)


if __name__ == "__main__":
    project_tmp = (REPO / "tmp").resolve()
    prefix = PREFIX.resolve()
    if not prefix.is_relative_to(project_tmp):
        raise RuntimeError(f"依赖安装前缀必须位于项目 tmp 内: {prefix}")
    PREFIX.mkdir(parents=True, exist_ok=True)
    (PREFIX / "lib/pkgconfig").mkdir(parents=True, exist_ok=True)
    for child in (ROOT / "prefix").iterdir():
        target = PREFIX / child.name
        if child.is_dir():
            shutil.copytree(
                child,
                target,
                dirs_exist_ok=True,
                copy_function=copy_overwrite,
            )
        elif not target.exists():
            shutil.copy2(child, target)
    for pc in (PREFIX / "lib/pkgconfig").glob("*.pc"):
        text = pc.read_text(encoding="utf-8")
        updated = text.replace("prefix=/\n", f"prefix={PREFIX.as_posix()}\n", 1)
        if updated != text:
            pc.chmod(0o666)
            pc.write_text(updated, encoding="utf-8")
    meson_build("libass-arm64", [
        "-Dfontconfig=disabled", "-Ddirectwrite=disabled", "-Dcoretext=disabled",
        "-Drequire-system-font-provider=false", "-Dasm=disabled", "-Dtest=disabled",
        "-Dcompare=disabled", "-Dprofile=disabled", "-Dfuzz=disabled",
        "-Dcheckasm=disabled", "-Ddefault_library=static",
    ])
    meson_build("libplacebo-arm64", [
        "-Ddemos=false", "-Dtests=false", "-Dvulkan=disabled", "-Dvk-proc-addr=disabled",
        "-Dopengl=enabled", "-Dgl-proc-addr=enabled", "-Dd3d11=disabled",
        "-Dglslang=disabled", "-Dshaderc=disabled", "-Dlcms=disabled",
        "-Dlibdovi=disabled", "-Dunwind=disabled", "-Dxxhash=disabled",
        "-Ddefault_library=static",
    ])
    prepare_ffmpeg()
    # libplacebo 的 convert.cc 使用 C++ 数值转换，静态归档需要显式带上
    # NDK 的 C++ 运行时依赖，供 libmpv.so 的 C 链接步骤解析。
    prepare_libplacebo_pc()
    build_mpv()
