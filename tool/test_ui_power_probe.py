"""界面采样必须排除锁屏、后台与未完成帧。"""

import unittest

from ui_power_probe import foreground_errors, parse_stat, present_times


class UiPowerProbeTest(unittest.TestCase):
    def test_accepts_visible_unlocked_screen(self):
        context = {"display": "mScreenState=ON", "policy": "mIsShowing=false",
                   "activity": "ResumedActivity: ActivityRecord{x com.maxzrb.piliexo/.MainActivity mVisible=true}"}
        self.assertEqual(foreground_errors(context), [])

    def test_rejects_doze_locked_and_hidden_app(self):
        context = {"display": "mScreenState=DOZE", "policy": "mIsShowing=true",
                   "activity": "ResumedActivity: ActivityRecord{x com.maxzrb.piliexo/.MainActivity mVisible=false}"}
        self.assertEqual(len(foreground_errors(context)), 3)

    def test_rejects_other_foreground_app(self):
        context = {"display": "mScreenState=ON", "policy": "mIsShowing=false",
                   "activity": "ResumedActivity: ActivityRecord{x com.example/.MainActivity mVisible=true}"}
        self.assertIn("应用未在可见前台", foreground_errors(context))

    def test_excludes_empty_pending_and_duplicate_frames(self):
        text = "8333333\n0 0 0\n1 20 3\n1 20 3\n1 9223372036854775807 3\n"
        self.assertEqual(present_times(text), {20})

    def test_thread_name_with_spaces_keeps_cpu_fields(self):
        fields = ["S"] + ["0"] * 10 + ["23", "7"] + ["0"] * 10
        result = parse_stat("12 (worker (codec)) " + " ".join(fields))
        self.assertEqual(result, {"tid": 12, "name": "worker (codec)", "ticks": 30})


if __name__ == "__main__":
    unittest.main()
