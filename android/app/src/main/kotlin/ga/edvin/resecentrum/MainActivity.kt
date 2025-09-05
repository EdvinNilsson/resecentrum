package ga.edvin.resecentrum

import android.Manifest.permission.ACCESS_COARSE_LOCATION
import android.Manifest.permission.ACCESS_FINE_LOCATION
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.app.PendingIntent.FLAG_IMMUTABLE
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.location.Location
import android.location.LocationManager
import android.os.Build.VERSION
import android.os.Build.VERSION_CODES
import android.os.Bundle
import android.os.CancellationSignal
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RequiresPermission
import androidx.core.app.ActivityCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.net.toUri
import androidx.core.util.Consumer
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

const val CHANNEL = "ga.edvin.resecentrum"

class MainActivity : FlutterFragmentActivity() {
    private lateinit var locationManager: LocationManager
    private val executor: Executor = Executor { command -> command.run() }
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        ).setMethodCallHandler { call, result ->
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

                "location" -> {
                    val requestPermissions = call.argument<Boolean>("requestPermissions")
                    if (requestPermissions != null) requestLocation(result, requestPermissions)
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

            val pinShortcutInfo =
                ShortcutInfo.Builder(this, (uri.hashCode() + label.hashCode()).toString(16))
                    .setShortLabel(label).setIntent(Intent(Intent.ACTION_VIEW, uri.toUri()))
                    .setIcon(Icon.createWithResource(this, drawable)).build()

            val pinnedShortcutCallbackIntent =
                shortcutManager.createShortcutResultIntent(pinShortcutInfo)

            val successCallback =
                PendingIntent.getBroadcast(this, 0, pinnedShortcutCallbackIntent, FLAG_IMMUTABLE)

            shortcutManager.requestPinShortcut(pinShortcutInfo, successCallback.intentSender)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        locationManager = getSystemService(LocationManager::class.java)
    }

    @SuppressLint("MissingPermission")
    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { permissions ->
            val result = pendingResult

            val gotFine = permissions.getOrDefault(ACCESS_FINE_LOCATION, false)
            val gotCoarse = permissions.getOrDefault(ACCESS_COARSE_LOCATION, false)

            if ((gotFine || gotCoarse) && result != null) {
                getCurrentLocation(result)
            } else {
                result?.error("LOCATION", "Saknar behörighet för platstjänst", null)
            }

            pendingResult = null
        }

    private fun requestLocation(result: MethodChannel.Result, requestPermissions: Boolean) {
        pendingResult = result

        if (!LocationManagerCompat.isLocationEnabled(locationManager)) {
            result.error("LOCATION", "Platstjänst är avaktiverat", null)
            pendingResult = null
            return
        }

        when {
            ActivityCompat.checkSelfPermission(
                this, ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED -> {
                getCurrentLocation(result)
            }

            requestPermissions -> {
                requestPermissionLauncher.launch(
                    arrayOf(
                        ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION
                    )
                )
            }

            ActivityCompat.checkSelfPermission(
                this, ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED -> {
                getCurrentLocation(result)
            }

            else -> {
                result.error("LOCATION", "Saknar behörighet för platstjänst", null)
            }
        }
    }

    @RequiresPermission(anyOf = [ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION])
    private fun getCurrentLocation(result: MethodChannel.Result) {
        val provider = when {
            ActivityCompat.checkSelfPermission(
                this, ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED && locationManager.isProviderEnabled(
                LocationManager.GPS_PROVIDER
            ) -> LocationManager.GPS_PROVIDER

            locationManager.isProviderEnabled(
                LocationManager.FUSED_PROVIDER
            ) && VERSION.SDK_INT >= VERSION_CODES.S -> LocationManager.FUSED_PROVIDER

            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> LocationManager.PASSIVE_PROVIDER
        }

        val consumer = Consumer { location: Location? ->
            val location = location ?: locationManager.getLastKnownLocation(provider)
            if (location != null) {
                result.success(doubleArrayOf(location.latitude, location.longitude))
            } else {
                result.error("LOCATION", null, null)
            }
            pendingResult = null
        }

        if (provider != LocationManager.GPS_PROVIDER) {
            val location = locationManager.getLastKnownLocation(provider)
            if (location != null) consumer.accept(location)
        }

        LocationManagerCompat.getCurrentLocation(
            locationManager, provider, CancellationSignal(), executor, consumer
        )
    }
}
