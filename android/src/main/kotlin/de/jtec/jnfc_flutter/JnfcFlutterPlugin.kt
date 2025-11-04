package de.jtec.jnfc_flutter

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding


/** JnfcFlutterPlugin */
class JnfcFlutterPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "jnfc_flutter")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "jnfc_flutter/events")
        eventChannel.setStreamHandler(this)
    }


    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ActivityAware (needed later for real NFC; kept minimal here)
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivity() {}

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }

            "startReading" -> {
                // MOCK: simulate detecting a card after 1s
                mainHandler.postDelayed({
                    val data = mapOf(
                        "uid" to "DE:AD:BE:EF",
                        "content" to "Hello from Android mock"
                    )
                    // invokeMethod back to Flutter to simulate a callback
                    channel.invokeMethod("onCardRead", data)
                }, 1000)
                result.success(null)
            }

            "startWriting" -> {
                val args = call.arguments as? Map<*, *>
                val uid = args?.get("uid") as? String ?: ""
                val content = args?.get("content") as? String ?: ""

                // MOCK: simulate write success after 0.8s
                mainHandler.postDelayed({
                    val response = mapOf(
                        "success" to true,
                        "error" to null
                    )
                    channel.invokeMethod("onWriteResult", response)
                }, 800)
                result.success(null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }


    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
