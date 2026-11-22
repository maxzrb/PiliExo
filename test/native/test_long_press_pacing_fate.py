"""从正式补丁编译原生策略，逐字比较固定输入的标准输出。"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


class LongPressPacingFateTest(unittest.TestCase):
    def test_fixed_samples(self):
        compiler = shutil.which('cc') or shutil.which('gcc') or shutil.which('clang')
        if not compiler:
            self.skipTest('需要本机 C 编译器运行固定样本')
        root = Path(__file__).resolve().parents[2]
        fixtures = root / 'test/fixtures/mpv_frame_drop_policy'
        patches = root / 'patches/mpv'
        headers = {
            'mpv-android-audio-clock.patch': 'player/piliexo_audio_clock.h',
            'mpv-android-codec-operating-rate.patch': 'player/piliexo_codec_rate.h',
            'ffmpeg-android-dynamic-hdr.patch': 'libavcodec/piliexo_decode_budget.h',
        }
        with tempfile.TemporaryDirectory(prefix='piliexo-fate-') as work:
            directory = Path(work)
            for filename, header in headers.items():
                diff = (patches / filename).read_text(encoding='utf-8')
                addition = diff.split(f'+++ b/{header}\n', 1)[1].split('\n--- ', 1)[0]
                code = '\n'.join(line[1:] for line in addition.splitlines()
                                 if line.startswith('+'))
                (directory / Path(header).name).write_text(code + '\n', encoding='utf-8')
            diff = (patches / 'ffmpeg-android-dynamic-hdr.patch').read_text(encoding='utf-8')
            start = diff.index('+static const uint8_t *piliexo_annexb_start_code')
            end = diff.index('+static int piliexo_receive_and_measure', start)
            parser = '\n'.join(line[1:] for line in diff[start:end].splitlines()
                               if line.startswith('+'))
            (directory / 'piliexo_nonref_au.h').write_text(parser + '\n', encoding='utf-8')
            binary = directory / ('fate.exe' if os.name == 'nt' else 'fate')
            subprocess.run(
                [compiler, '-std=c11', '-Wall', '-Wextra', '-Werror',
                 '-I', str(directory), str(root / 'test/native/long_press_pacing_fate.c'),
                 '-lm', '-o', str(binary)], check=True,
            )
            actual = subprocess.check_output(
                [str(binary)], text=True, encoding='utf-8',
                input=(fixtures / 'long-press-pacing.txt').read_text(encoding='utf-8'),
            )
        reference = (root / 'test/ref/fate/mpv-long-press-pacing').read_text(encoding='utf-8')
        self.assertMultiLineEqual(reference, actual)
