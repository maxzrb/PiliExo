"""编译补丁中的实际采样率策略，验证高采样率、直通和低延迟边界。"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest


class AudioTrackRatePolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which('cc') or shutil.which('gcc') or shutil.which('clang')
        if not compiler:
            raise unittest.SkipTest('需要本机 C 编译器验证原生策略')
        patch = (Path(__file__).resolve().parents[2] / 'patches/mpv/audiotrack-low-latency-experiment.patch').read_text(encoding='utf-8')
        added = '\n'.join(line[1:] for line in patch.splitlines() if line.startswith(('+', ' ')) and not line.startswith('+++'))
        functions = []
        for name in ['fast_path', 'rate']:
            match = re.search(r'static (?:bool|int) piliexo_audiotrack_' + name + r'\([\s\S]*?\n\}', added)
            if match is None:
                raise AssertionError('补丁缺少实际策略函数：' + name)
            functions.append(match.group())
        cls.work = tempfile.TemporaryDirectory(prefix='piliexo-audiotrack-policy-')
        cls.addClassCleanup(cls.work.cleanup)
        root = Path(cls.work.name)
        source = root / 'policy.c'
        source.write_text('#include <stdbool.h>\n#include <stdio.h>\n#include <stdlib.h>\n' + '\n'.join(functions) + '''
int main(int argc, char **argv) {
    if (argc != 7) return 2;
    int a = atoi(argv[2]), b = atoi(argv[3]), c = atoi(argv[4]);
    int d = atoi(argv[5]), e = atoi(argv[6]);
    int result = argv[1][0] == 'r'
        ? piliexo_audiotrack_rate(a, b, c, d, e)
        : piliexo_audiotrack_fast_path(a, b, c, d);
    printf("%d", result);
    return 0;
}
''', encoding='utf-8')
        cls.binary = root / ('policy.exe' if os.name == 'nt' else 'policy')
        subprocess.run([compiler, '-std=c11', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(cls.binary)], check=True, capture_output=True)

    def rate(self, requested, native, adaptive=True, pcm=True, fast=True):
        return int(subprocess.check_output([str(self.binary), 'rate', *map(str, [requested, native, int(adaptive), int(pcm), int(fast)])], text=True))

    def fast(self, rate, channels=2, adaptive=True, pcm=True):
        return bool(int(subprocess.check_output([str(self.binary), 'fast', *map(str, [rate, channels, int(adaptive), int(pcm), 0])], text=True)))

    def test_hires_not_forced_to_native_rate(self):
        for requested in [88200, 96000, 176400, 192000]:
            for native in [44100, 48000, 96000]:
                with self.subTest(requested=requested, native=native):
                    self.assertEqual(self.rate(requested, native), requested)
                    self.assertFalse(self.fast(requested))

    def test_normal_pcm_matches_supported_low_latency_rate(self):
        self.assertEqual(self.rate(44100, 48000), 48000)
        self.assertEqual(self.rate(48000, 44100), 44100)
        self.assertEqual(self.rate(32000, 48000), 48000)
        self.assertTrue(self.fast(44100))
        self.assertTrue(self.fast(48000, channels=1))

    def test_passthrough_and_multichannel_bypass_fast_path(self):
        self.assertEqual(self.rate(192000, 48000, pcm=False), 192000)
        self.assertFalse(self.fast(48000, pcm=False))
        self.assertFalse(self.fast(48000, channels=6))

    def test_missing_capability_keeps_requested_rate(self):
        self.assertEqual(self.rate(44100, 48000, fast=False), 44100)
        self.assertEqual(self.rate(96000, 0), 96000)
        self.assertEqual(self.rate(44100, 96000), 44100)

    def test_experiment_disabled_preserves_legacy_policy(self):
        self.assertEqual(self.rate(96000, 48000, adaptive=False), 48000)
        self.assertEqual(self.rate(44100, 48000, adaptive=False), 44100)


if __name__ == '__main__':
    unittest.main()
