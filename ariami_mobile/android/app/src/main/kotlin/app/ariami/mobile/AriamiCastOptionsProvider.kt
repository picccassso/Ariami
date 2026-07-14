package app.ariami.mobile

import android.content.Context
import com.felnanuke.google_cast.GoogleCastOptionsProvider
import com.google.android.gms.cast.LaunchOptions
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions

/**
 * Supplies Cast options with the SDK media notification disabled so Ariami's
 * audio_service notification owns lock-screen / shade controls during cast.
 */
class AriamiCastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions {
        val receiverApplicationId = try {
            GoogleCastOptionsProvider.options.receiverApplicationId
        } catch (e: UninitializedPropertyAccessException) {
            DEFAULT_MEDIA_RECEIVER_APPLICATION_ID
        }

        val launchOptions = LaunchOptions.Builder()
            .setAndroidReceiverCompatible(true)
            .build()

        return CastOptions.Builder()
            .setReceiverApplicationId(receiverApplicationId)
            .setLaunchOptions(launchOptions)
            .setResumeSavedSession(true)
            .setEnableReconnectionService(true)
            .setCastMediaOptions(buildMediaOptionsWithoutNotification())
            .build()
    }

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? {
        return null
    }

    private fun buildMediaOptionsWithoutNotification(): CastMediaOptions {
        return CastMediaOptions.Builder()
            .setNotificationOptions(null)
            .setMediaSessionEnabled(false)
            .build()
    }

    companion object {
        private const val DEFAULT_MEDIA_RECEIVER_APPLICATION_ID = "CC1AD845"
    }
}
