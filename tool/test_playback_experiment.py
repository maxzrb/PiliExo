"""倍速验收日志必须隔离视频、音频与不同应用进程。"""

import unittest

from playback_experiment import diagnostic_pid, video_codec_rows


class VideoCodecIsolationTest(unittest.TestCase):
    def test_video_statistics_do_not_average_audio_or_other_process(self):
        text = "\n".join([
            '1000.000 42 43 I flutter: PILI_PLAYBACK {"event":"sample"}',
            '1000.001 42 44 W TraceLog: tick(c2.qti.hevc.decoder:0x1) Queued: 180.0/s Done: 180.0/s Rendered: 179.0/s Discarded: 1.0/s',
            '1000.002 42 45 W TraceLog: tick(c2.android.aac.decoder:0x2) Queued: 30.0/s Done: 30.0/s Rendered: 0.0/s Discarded: 0.0/s',
            '1000.003 99 98 W TraceLog: tick(c2.qti.hevc.decoder:0x3) Queued: 9.0/s Done: 9.0/s Rendered: 9.0/s Discarded: 0.0/s',
        ])
        self.assertEqual(diagnostic_pid(text), 42)
        self.assertEqual(video_codec_rows(text, 42, 'c2.qti.hevc.decoder'),
                         [[1000.001, 180, 180, 179, 1]])

    def test_unknown_or_ambiguous_process_never_becomes_zero_drops(self):
        text = '\n'.join(f'1000.0 {pid} 43 I flutter: PILI_PLAYBACK {{}}' for pid in [42, 99])
        self.assertIsNone(diagnostic_pid(text))
        self.assertIsNone(diagnostic_pid(''))
        self.assertEqual(video_codec_rows(text, None, 'c2.qti.hevc.decoder'), [])


if __name__ == '__main__':
    unittest.main()
