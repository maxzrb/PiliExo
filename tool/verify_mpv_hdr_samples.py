"""以固定媒体输入和参考输出核验 P5 元数据及软件解码，不启动测试应用。"""
from pathlib import Path
import argparse
import difflib
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / 'test/fixtures/mpv_hdr'
REFERENCES = ROOT / 'test/ref/fate'


def run(command):
    result = subprocess.run(command, capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace')[-3000:])
    return result.stdout


def metadata_reference(probe):
    stream = probe['streams'][0]
    dovi = next(side for side in stream['side_data_list']
                if side['side_data_type'] == 'DOVI configuration record')
    lines = [f"codec={stream['codec_name']} size={stream['width']}x{stream['height']} pixel={stream['pix_fmt']}",
             f"profile={dovi['dv_profile']} level={dovi['dv_level']} rpu={dovi['rpu_present_flag']} el={dovi['el_present_flag']} bl={dovi['bl_present_flag']} compatible={dovi['dv_bl_signal_compatibility_id']}"]
    for index, frame in enumerate(probe['frames']):
        sides = frame.get('side_data_list', [])
        data = next((side for side in sides if side['side_data_type'] == 'Dolby Vision Metadata'), {})
        rpu = int(any(side['side_data_type'] == 'Dolby Vision RPU Data' for side in sides))
        lines.append(f"frame={index} rpu={rpu} metadata={int(bool(data))} baseBits={data.get('bl_bit_depth')} signalBits={data.get('signal_bit_depth')} colorSpace={data.get('signal_color_space')}")
    return '\n'.join(lines)+'\n'


def compare(name, actual, output):
    expected = (REFERENCES/name).read_text(encoding='utf-8')
    (output/name).write_text(actual, encoding='utf-8')
    if actual != expected:
        print(''.join(difflib.unified_diff(expected.splitlines(True), actual.splitlines(True),
                                         fromfile='reference/'+name, tofile='actual/'+name)))
        raise AssertionError(name+' 与参考输出不一致')
    print('PASS', name)


def verify_device_loop(ffmpeg, sample, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([
        ffmpeg, '-v', 'error', '-y', '-strict', 'unofficial',
        '-stream_loop', '599', '-i', str(sample), '-t', '10',
        '-map', '0:v:0', '-c:v', 'copy', '-an', '-strict', 'unofficial',
        '-movflags', '+faststart', str(output),
    ], capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace')[-3000:])
    probe = json.loads(run([
        'ffprobe', '-v', 'error', '-show_streams', '-show_frames',
        '-read_intervals', '%+#5', '-of', 'json', str(output),
    ]))
    stream = probe['streams'][0]
    dovi = next((side for side in stream.get('side_data_list', [])
                 if side['side_data_type'] == 'DOVI configuration record'), None)
    assert dovi is not None and dovi['dv_profile'] == 5, '循环样本缺少 Profile5 dvcC'
    assert int(stream['nb_frames']) == 602, stream['nb_frames']
    for index, frame in enumerate(probe['frames']):
        sides = frame.get('side_data_list', [])
        assert any(side['side_data_type'] == 'Dolby Vision RPU Data' for side in sides), index
        assert any(side['side_data_type'] == 'Dolby Vision Metadata' for side in sides), index
    decoded = subprocess.run(
        [ffmpeg, '-v', 'error', '-xerror', '-i', str(output), '-frames:v', '600', '-f', 'null', '-'],
        capture_output=True, timeout=90,
    )
    if decoded.returncode or decoded.stderr:
        raise RuntimeError(decoded.stderr.decode('utf-8', errors='replace')[-3000:])
    print(f'PASS 10秒设备循环样本 {output}（602帧，dvcC/RPU保留，软件解码无错误）')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', default='ffmpeg')
    parser.add_argument('--ffprobe', default='ffprobe')
    parser.add_argument('--output', type=Path, default=ROOT/'tmp/mpv-hdr-fate')
    parser.add_argument('--libplacebo', action='store_true', help='另测本机 Vulkan/libplacebo 的 P5 颜色修正参考点')
    parser.add_argument('--loop-output', type=Path, help='生成并核验仅用于覆盖层真机回归的10秒无损循环样本')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((FIXTURES/'sample.json').read_text(encoding='utf-8'))
    sample = FIXTURES/manifest['file']
    assert hashlib.sha256(sample.read_bytes()).hexdigest() == manifest['sha256'], '输入样本 SHA-256 不匹配'
    probe = json.loads(run([args.ffprobe, '-v', 'error', '-show_streams', '-show_frames',
                            '-read_intervals', '%+#5', '-of', 'json', str(sample)]))
    compare('mpv-hdr-dv-p5-metadata', metadata_reference(probe), args.output)
    decoded = run([args.ffmpeg, '-v', 'error', '-bitexact', '-flags', '+bitexact',
                   '-i', str(sample), '-map', '0:v:0', '-frames:v', '5', '-an',
                   '-pix_fmt', 'yuv420p10le', '-f', 'framemd5', '-']).decode('utf-8')
    rows = '\n'.join(line for line in decoded.splitlines() if line and not line.startswith('#'))+'\n'
    compare('mpv-hdr-dv-p5-framemd5', rows, args.output)
    if args.libplacebo:
        raw = run([args.ffmpeg, '-v', 'error', '-init_hw_device', 'vulkan=vk:0',
                   '-filter_hw_device', 'vk', '-i', str(sample), '-vf',
                   'format=p010le,hwupload,libplacebo=apply_dolbyvision=1:colorspace=bt709:color_primaries=bt709:color_trc=bt709:format=yuv420p,hwdownload,format=yuv420p,format=rgb24',
                   '-frames:v', '1', '-f', 'rawvideo', '-'])
        reference = json.loads((REFERENCES/'mpv-hdr-dv-p5-rgb.json').read_text(encoding='utf-8'))
        for point in reference['points']:
            offset = (point['y']*1920+point['x'])*3
            actual = list(raw[offset:offset+3])
            assert len(actual) == 3 and max(abs(a-b) for a, b in zip(actual, point['rgb'])) <= reference['tolerance'], (point, actual)
        print('PASS mpv-hdr-dv-p5-rgb（本机 Vulkan/libplacebo 参考；不替代 Android 真机验收）')
    if args.loop_output:
        verify_device_loop(args.ffmpeg, sample, args.loop_output)
    print('固定 P5 样本与参考输出核验完成')


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
