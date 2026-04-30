package com.example.ariami_mobile

import android.util.Log
import com.google.android.gms.cast.framework.CastContext
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private val nativeDownloadChannel = "ariami/native_downloads"
    private var castStopRequestedForClose = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativeDownloadChannel)
            .setMethodCallHandler(NativeDownloadBridge(applicationContext))
    }

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        return super.provideFlutterEngine(context)
    }

    override fun onStop() {
        stopCastIfAppIsClosing("onStop")
        super.onStop()
    }

    override fun onDestroy() {
        stopCastIfAppIsClosing("onDestroy")
        super.onDestroy()
    }

    private fun stopCastIfAppIsClosing(source: String) {
        if (!isFinishing || castStopRequestedForClose) {
            return
        }

        castStopRequestedForClose = true
        try {
            val sessionManager = CastContext.getSharedInstance(applicationContext).sessionManager
            val castSession = sessionManager.currentCastSession
            if (castSession != null) {
                Log.d("AriamiCast", "Stopping cast playback during app close ($source)")
                castSession.remoteMediaClient?.stop()
                sessionManager.endCurrentSession(true)
            }
        } catch (e: Exception) {
            Log.w("AriamiCast", "Failed to stop cast playback during app close ($source)", e)
        }
    }
}
