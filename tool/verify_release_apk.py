"""发布 APK 静态门禁：检查插件注册、AOT 来源和双 ABI 必要文件。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys
import zipfile


ROOT = Path(__file__).resolve().parent.parent
REGISTRANT = b"io/flutter/plugins/GeneratedPluginRegistrant"
SUPPORTED_ABIS = {"arm64-v8a", "armeabi-v7a"}


def inspect_apk(path: Path, source_commit: str, version: str):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        dex = b"".join(
            archive.read(name)
            for name in names
            if re.fullmatch(r"classes\d*\.dex", name)
        )
        if REGISTRANT not in dex:
            raise RuntimeError("classes.dex 缺少 GeneratedPluginRegistrant")

        abis = {
            name.split("/")[1]
            for name in names
            if name.startswith("lib/") and name.count("/") >= 2
        } & SUPPORTED_ABIS
        if len(abis) != 1:
            raise RuntimeError(f"APK ABI 数量异常：{sorted(abis)}")
        abi = next(iter(abis))
        required = {
            f"lib/{abi}/libapp.so",
            f"lib/{abi}/libmpv.so",
            f"lib/{abi}/libffmpegJNI.so",
        }
        missing = required - set(names)
        if missing:
            raise RuntimeError(f"APK 缺少必要文件：{sorted(missing)}")

        app = archive.read(f"lib/{abi}/libapp.so")
        if source_commit.encode() not in app:
            raise RuntimeError("AOT 内嵌源码提交与预期不一致")
        if version.encode() not in app:
            raise RuntimeError("AOT 内嵌版本名与预期不一致")
        if any("fixtures/" in name or "dv-p5" in name for name in names):
            raise RuntimeError("APK 误包含测试媒体")

        raw = path.read_bytes()
        return {
            "apk": path.name,
            "abi": abi,
            "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "sourceCommit": source_commit,
            "version": version,
            "generatedPluginRegistrant": True,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apks", type=Path, nargs="+")
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--version", default="26.11.11")
    args = parser.parse_args()

    registrant = (
        ROOT
        / "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
    )
    plugin_manifest = ROOT / ".flutter-plugins-dependencies"
    if not registrant.is_file() or not plugin_manifest.is_file():
        raise SystemExit("缺少 Android 插件注册源文件或依赖清单")

    results = [
        inspect_apk(path.resolve(strict=True), args.source_commit, args.version)
        for path in args.apks
    ]
    if len({result["abi"] for result in results}) != len(results):
        raise SystemExit("发布 APK 存在重复 ABI")
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, zipfile.BadZipFile) as error:
        print(f"发布 APK 校验失败：{error}", file=sys.stderr)
        raise SystemExit(1)
