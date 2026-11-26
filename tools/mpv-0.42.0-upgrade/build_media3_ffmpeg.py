"""用 mpv 源码清单固定的 FFmpeg 重编 Media3 杜比音频扩展。"""

from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.request import urlretrieve
import zipfile


ROOT = Path(__file__).resolve().parents[2]
MPV_TOOLS = ROOT / "tools/mpv-0.42.0-upgrade"
NDK = Path("C:/Android/Sdk/ndk/28.2.13676358")
LLVM = NDK / "toolchains/llvm/prebuilt/windows-x86_64/bin"
GIT_USR_BIN = Path("C:/Program Files/Git/usr/bin")
MEDIA3_VERSION = "1.11.0"
JNI_SHA256 = "cebafb59c70cd7082d40a94d33680f8627547994758fbd8551ab4b3434d4088c"
AAR_NAME = f"media3-decoder-ffmpeg-{MEDIA3_VERSION}-ac3-eac3-truehd.aar"
DECODERS = {"ac3", "eac3", "truehd"}
TARGETS = {
    "arm64-v8a": "aarch64-linux-android24",
    "armeabi-v7a": "armv7a-linux-androideabi24",
}


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def fetch_verified(url, path, sha256, size=None):
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".download")
        urlretrieve(url, temporary)
        if digest(temporary) != sha256 or (size is not None and temporary.stat().st_size != size):
            raise ValueError(f"下载的源码校验失败：{path.name}")
        temporary.replace(path)
    if digest(path) != sha256 or (size is not None and path.stat().st_size != size):
        raise ValueError(f"本地源码校验失败：{path.name}")


def ffmpeg_pin():
    components = json.loads((ROOT / "patches/mpv/sources.json").read_text(encoding="utf-8"))
    return next(component for component in components if component["name"] == "ffmpeg")


def config_flags():
    return [
        "--prefix='PROJECT_PREFIX'",
        "--target-os=android",
        "--enable-cross-compile",
        "--arch=aarch64",
        "--cpu=armv8-a",
        "--cc=aarch64-linux-android24-clang",
        "--cxx=aarch64-linux-android24-clang++",
        "--ar=llvm-ar",
        "--ranlib=llvm-ranlib",
        "--nm=llvm-nm",
        "--strip=llvm-strip",
        "--disable-autodetect",
        "--disable-network",
        "--disable-programs",
        "--disable-doc",
        "--disable-everything",
        "--disable-avdevice",
        "--disable-avfilter",
        "--disable-avformat",
        "--disable-swscale",
        "--disable-shared",
        "--enable-static",
        "--enable-pic",
        "--enable-small",
        "--enable-swresample",
        "--enable-decoder=" + ",".join(sorted(DECODERS)),
    ]


def build_native(work, archive, jni, commit, abi):
    base = work / abi
    source = base / "source"
    prefix = base / "prefix"
    source.mkdir(parents=True)
    prefix.mkdir()
    subprocess.run(["tar.exe", "-xzf", str(archive), "--strip-components", "1", "-C", str(source)],
                   check=True)
    (source / "ffbuild/tmp").mkdir(exist_ok=True)
    release = (source / "RELEASE").read_text(encoding="utf-8").strip()
    env = os.environ.copy()
    env.update(
        PATH=os.pathsep.join([str(GIT_USR_BIN), str(LLVM), env["PATH"]]),
        FFMPEG_ANDROID_ABI=abi,
        FFMPEG_SOURCE_DIR=str(source),
        FFMPEG_INSTALL_PREFIX=str(prefix),
        FFMPEG_SKIP_CONFIGURE="1",
        FFMPEG_MAKE_TARGET="all",
        FFMPEG_MAKE_FLAGS="",
        FFMPEG_BUILD_JOBS="4",
        FFMPEG_REVISION=f"{release}-{commit[:8]}",
    )
    with (base / "build.log").open("w", encoding="utf-8") as log:
        common = {"cwd": ROOT, "stdout": log, "stderr": subprocess.STDOUT, "env": env, "check": True}
        try:
            subprocess.run([sys.executable, str(MPV_TOOLS / "run_ffmpeg_configure.py"),
                            str(ROOT), " ".join(config_flags()), str(source), str(prefix)], **common)
            subprocess.run(["cmd.exe", "/d", "/c", r"tools\mpv-0.42.0-upgrade\build_ffmpeg_with_vs.cmd"],
                           **common)
            enabled = set(re.findall(
                r"^#define CONFIG_([A-Z0-9]+)_DECODER 1$",
                (source / "config_components.h").read_text(encoding="utf-8"), re.M))
            if enabled != {name.upper() for name in DECODERS}:
                raise ValueError(f"{abi} 启用的解码器异常：{sorted(enabled)}")
            library = base / "libffmpegJNI.so"
            subprocess.run([
                str(LLVM / "clang++.exe"), f"--target={TARGETS[abi]}",
                "-std=c++17", "-O2", "-fPIC", "-shared", "-fvisibility=hidden", "-static-libstdc++",
                "-Wl,--no-undefined", "-Wl,--exclude-libs,ALL", "-Wl,-z,max-page-size=16384",
                "-Wl,-soname,libffmpegJNI.so", "-Wl,-Bsymbolic",
                "-I", str(source), str(jni), "-o", str(library),
                str(source / "libswresample/libswresample.a"),
                str(source / "libavcodec/libavcodec.a"),
                str(source / "libavutil/libavutil.a"), "-landroid", "-llog", "-lm",
            ], **common)
            subprocess.run([str(LLVM / "llvm-strip.exe"), "--strip-unneeded", str(library)], **common)
        except subprocess.CalledProcessError as error:
            raise RuntimeError(f"{abi} 构建失败，见 {base / 'build.log'}") from error
    return library


def main():
    pin = ffmpeg_pin()
    commit = pin["commit"]
    temporary = ROOT / "tmp"
    temporary.mkdir(exist_ok=True)
    archive = temporary / f"FFmpeg-{commit}.tar.gz"
    fetch_verified(f"https://codeload.github.com/{pin['repo']}/tar.gz/{commit}", archive,
                   pin["archiveSha256"], pin["bytes"])

    work = Path(tempfile.mkdtemp(prefix=f"media3-ffmpeg-{commit[:8]}-", dir=temporary))
    print(f"工作目录 {work}", flush=True)
    jni = work / "ffmpeg_jni.cc"
    fetch_verified(f"https://raw.githubusercontent.com/androidx/media/{MEDIA3_VERSION}/"
                   "libraries/decoder_ffmpeg/src/main/jni/ffmpeg_jni.cc", jni, JNI_SHA256)
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = {abi: executor.submit(build_native, work, archive, jni, commit, abi)
                   for abi in TARGETS}
        libraries = {f"jni/{abi}/libffmpegJNI.so": future.result()
                     for abi, future in futures.items()}

    template = ROOT / "android/app/libs" / AAR_NAME
    payload = work / AAR_NAME
    with zipfile.ZipFile(template) as original, zipfile.ZipFile(payload, "w") as target:
        if set(libraries) != {name for name in original.namelist() if name.endswith(".so")}:
            raise ValueError("现有 AAR 的原生库清单与构建目标不一致")
        for entry in original.infolist():
            lib = libraries.get(entry.filename)
            target.writestr(entry, lib.read_bytes() if lib else original.read(entry))
    print(f"{payload}\nSHA-256 {digest(payload)}", flush=True)


if __name__ == "__main__":
    main()
