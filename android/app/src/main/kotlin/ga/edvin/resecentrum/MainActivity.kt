package ga.edvin.resecentrum

import io.flutter.embedding.android.FlutterActivity
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import android.app.PendingIntent
import android.app.PendingIntent.FLAG_IMMUTABLE
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build.VERSION
import android.os.Build.VERSION_CODES
import android.net.Uri

const val CHANNEL = "ga.edvin.resecentrum"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "createShortcut" -> {
                    val uri = call.argument<String>("uri")
                    val label = call.argument<String>("label")
                    val icon = call.argument<String>("icon")
                    if (uri != null && label != null && icon != null) {
                        createShortcut(uri, label, icon)
                    }
                    result.success(null)
                }
                "sdk" -> {
                    result.success(VERSION.SDK_INT)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun createShortcut(uri: String, label: String, icon: String) {
        if (VERSION.SDK_INT < VERSION_CODES.O) return

        val shortcutManager = getSystemService(ShortcutManager::class.java)

        if (shortcutManager!!.isRequestPinShortcutSupported) {
            val drawable = when (icon) {
                "tram" -> R.mipmap.ic_tram
                "train" -> R.mipmap.ic_train
                "boat" -> R.mipmap.ic_boat
                "trip" -> R.mipmap.ic_trip
                "my_location" -> R.mipmap.ic_my_location
                else -> R.mipmap.ic_bus
            }

            val pinShortcutInfo = ShortcutInfo.Builder(context, (uri.hashCode() + label.hashCode()).toString(16))
                .setShortLabel(label)
                .setIntent(Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
                .setIcon(Icon.createWithResource(context, drawable))
                .build()

            val pinnedShortcutCallbackIntent = shortcutManager.createShortcutResultIntent(pinShortcutInfo)

            val successCallback = PendingIntent.getBroadcast(context, 0, pinnedShortcutCallbackIntent, FLAG_IMMUTABLE)

            shortcutManager.requestPinShortcut(pinShortcutInfo, successCallback.intentSender)
        }
    }
}
