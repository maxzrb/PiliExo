#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
windows_project_root="$(cygpath -w "$project_root")"
export TMPDIR="ffbuild/tmp"
export TMP="$TMPDIR"
export TEMP="$TMPDIR"
export PATH="$project_root/tmp/mpv-0.42.0-upgrade/bin:/c/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin:/c/Android/Sdk/ndk/28.2.13676358/prebuilt/windows-x86_64/bin:$PATH"

source_dir="${FFMPEG_SOURCE_DIR:-$project_root/tmp/mpv-0.42.0-upgrade/ffmpeg}"
install_prefix="${FFMPEG_INSTALL_PREFIX:-$project_root/tmp/mpv-0.42.0-upgrade/prefix}"
if [[ "$source_dir" =~ ^[A-Za-z]:[\\/] ]]; then
    source_dir="$(cygpath -u "$source_dir")"
fi
if [[ "$install_prefix" =~ ^[A-Za-z]:[\\/] ]]; then
    install_prefix="$(cygpath -u "$install_prefix")"
fi
source_dir="$(cd "$source_dir" && pwd)"
mkdir -p "$install_prefix"
install_prefix="$(cd "$install_prefix" && pwd)"
source_dir_windows="$(cygpath -w "$source_dir")"
install_prefix_windows="$(cygpath -w "$install_prefix")"

export PKG_CONFIG_LIBDIR="$install_prefix/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$(cygpath -w "$install_prefix")"
export GIT_CEILING_DIRECTORIES="${GIT_CEILING_DIRECTORIES:-$(dirname "$source_dir")}"
export LC_ALL=C

cp -f /usr/bin/sort.exe "$project_root/tmp/mpv-0.42.0-upgrade/bin/sort.exe"
printf '#!/usr/bin/env bash\nexec python "%s/tools/mpv-0.42.0-upgrade/pkg-config.py" "$@"\n' "$project_root" > "$project_root/tmp/mpv-0.42.0-upgrade/bin/pkg-config"

flags="$(cat "$project_root/tools/mpv-0.42.0-upgrade/baseline-build-flags.txt")"

cd "$source_dir"
mkdir -p "$TMPDIR"
if [[ "${FFMPEG_SKIP_CONFIGURE:-0}" != "1" ]]; then
    # 每个配置参数由 Python 单独传入，项目路径中的空格不会触发二次拆分。
    # shellcheck disable=SC2086
    python "$project_root/tools/mpv-0.42.0-upgrade/run_ffmpeg_configure.py" \
        "$windows_project_root" "$flags" "$source_dir_windows" "$install_prefix_windows"
fi
# Windows 自带的 awk 无法可靠解析 cl.exe 的 -showIncludes 输出；
# 本临时构建不生成主机对象依赖文件，由下一次重编译完整覆盖。
make_flags=()
if [[ -n "${FFMPEG_MAKE_FLAGS:-}" ]]; then
    read -r -a make_flags <<< "$FFMPEG_MAKE_FLAGS"
fi
revision_flags=()
if [[ -n "${FFMPEG_REVISION:-}" ]]; then
    revision_flags=("REVISION=$FFMPEG_REVISION")
fi
make_target="${FFMPEG_MAKE_TARGET:-install}"
if [[ "$make_target" == "install" && -z "${FFMPEG_MAKE_FLAGS:-}" ]]; then
    make "-j${FFMPEG_BUILD_JOBS:-8}" "${revision_flags[@]}" HOSTCCDEP= all
    # FFmpeg 9.1 的静默安装宏在 Git Bash 下会被截断；安装阶段显式关闭静默模式。
    make "${revision_flags[@]}" HOSTCCDEP= V=1 install
else
    make "-j${FFMPEG_BUILD_JOBS:-8}" "${make_flags[@]}" \
        "${revision_flags[@]}" HOSTCCDEP= "$make_target"
fi
