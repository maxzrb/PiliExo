"""按校验过的源码清单应用正式 mpv/FFmpeg 补丁，不应用研究补丁。"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess


ROOT = Path(__file__).resolve().parent.parent
PATCHES = ROOT / "patches/mpv"


def patch_command(source, patch, *arguments):
    env = os.environ.copy()
    # 解压源码可能放在主仓库 tmp 中，禁止 git apply 意外使用主仓库根目录。
    env["GIT_CEILING_DIRECTORIES"] = str(source.parent)
    return subprocess.run(
        ["git", "apply", *arguments, str(patch)], cwd=source, env=env,
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mpv-source", type=Path)
    parser.add_argument("--ffmpeg-source", type=Path)
    parser.add_argument("--check", action="store_true", help="只检查清单和已应用补丁，不修改源码")
    args = parser.parse_args()
    manifest = json.loads((PATCHES / "sources.json").read_text(encoding="utf-8"))
    # 在修改任何源码之前，一次性校验全部正式补丁与研究补丁的身份。
    for component in manifest:
        for entry in component.get("patches", []) + component.get("researchPatches", []):
            patch = PATCHES / entry["file"]
            if patch.parent != PATCHES or hashlib.sha256(patch.read_bytes()).hexdigest() != entry["sha256"]:
                raise RuntimeError(f"补丁路径或 SHA-256 不匹配：{entry['file']}")
    sources = {"mpv": args.mpv_source, "ffmpeg": args.ffmpeg_source}
    for component in manifest:
        source = sources.get(component["name"])
        if source is None:
            continue
        source = source.resolve(strict=True)
        for entry in component.get("patches", []):
            patch = PATCHES / entry["file"]
            if patch_command(source, patch, "--reverse", "--check").returncode == 0:
                print(f"PASS 已应用 {component['name']}/{patch.name}")
                continue
            if args.check:
                raise RuntimeError(f"源码尚未应用正式补丁：{patch.name}")
            result = patch_command(source, patch, "--check")
            if result.returncode:
                raise RuntimeError(f"补丁与源码不兼容：{patch.name}\n{result.stderr}")
            result = patch_command(source, patch)
            if result.returncode:
                raise RuntimeError(result.stderr)
            print(f"PASS 应用 {component['name']}/{patch.name}")
    print("PASS 正式补丁清单 SHA-256；研究补丁未纳入应用列表")


if __name__ == "__main__":
    main()
