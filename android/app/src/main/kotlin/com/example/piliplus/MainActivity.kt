package com.example.piliplus

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var hdrMedia3Plugin: HdrMedia3Plugin? = null
    private var hapticFeedbackPlugin: HapticFeedbackPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hdrMedia3Plugin = HdrMedia3Plugin(this, flutterEngine.dartExecutor.binaryMessenger)
        hdrMedia3Plugin?.register(flutterEngine)
        hapticFeedbackPlugin = HapticFeedbackPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        hapticFeedbackPlugin?.register()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        hdrMedia3Plugin?.dispose()
        hdrMedia3Plugin = null
        hapticFeedbackPlugin?.dispose()
        hapticFeedbackPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onDestroy() {
        stopService(Intent(this, com.ryanheise.audioservice.AudioService::class.java))
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
    }
}
