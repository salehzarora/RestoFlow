package com.restoflow.kiosk

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

// KIOSK-001 Phase 1: an unattended customer kiosk must never let the screen
// sleep mid-order; immersive/portrait posture is applied from Dart
// (SystemChrome) so it survives hot reload and stays testable.
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
