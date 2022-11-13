package ga.edvin.resecentrum

import android.app.PendingIntent
import android.app.PendingIntent.FLAG_IMMUTABLE
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build.VERSION
import android.os.Build.VERSION_CODES
import androidx.annotation.NonNull
import com.google.android.material.timepicker.MaterialTimePicker
import com.google.android.material.timepicker.MaterialTimePicker.INPUT_MODE_CLOCK
import com.google.android.material.timepicker.TimeFormat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

const val CHANNEL = "ga.edvin.resecentrum"

class MainActivity : FlutterFragmentActivity() {
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
                "timePicker" -> {
                    val hour = call.argument<Int>("hour");
                    val minute = call.argument<Int>("minute");
                    if (hour != null && minute != null) {
                        timePicker(hour, minute, result)
                    }
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

            val pinShortcutInfo = ShortcutInfo.Builder(this, (uri.hashCode() + label.hashCode()).toString(16))
                .setShortLabel(label)
                .setIntent(Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
                .setIcon(Icon.createWithResource(this, drawable))
                .build()

            val pinnedShortcutCallbackIntent = shortcutManager.createShortcutResultIntent(pinShortcutInfo)

            val successCallback = PendingIntent.getBroadcast(this, 0, pinnedShortcutCallbackIntent, FLAG_IMMUTABLE)

            shortcutManager.requestPinShortcut(pinShortcutInfo, successCallback.intentSender)
        }
    }

    private fun timePicker(hour: Int, minute: Int, result: Result) {
        val picker =
            MaterialTimePicker.Builder()
                .setTimeFormat(TimeFormat.CLOCK_24H)
                .setInputMode(INPUT_MODE_CLOCK)
                .setHour(hour)
                .setMinute(minute)
                .build()

        picker.addOnPositiveButtonClickListener { result.success(intArrayOf(picker.hour, picker.minute)) }

        picker.addOnNegativeButtonClickListener { result.success(null) }
        picker.addOnCancelListener { result.success(null) }

        picker.show(supportFragmentManager, null)
    }
}
