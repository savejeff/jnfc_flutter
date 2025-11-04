package de.jtec.jnfc_flutter

import android.app.Activity
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result


/** JnfcFlutterPlugin */
class JnfcFlutterPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    NfcManager.Callbacks {

    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val nfc = NfcManager()

    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "jnfc_flutter")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        nfc.bind(binding.activity, this)
    }
    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        nfc.unbind()
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        nfc.bind(binding.activity, this)
    }
    override fun onDetachedFromActivity() {
        activity = null
        nfc.unbind()
    }

    // Method channel
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${Build.VERSION.RELEASE}")
            }

            "startReading" -> {
                nfc.startReading()
                result.success(null)
            }

            "stopReading" -> {
                nfc.stopReading()
                result.success(null)
            }

            "startWriting" -> {
                val args = call.arguments as? Map<*, *>
                val uid = args?.get("uid") as? String
                val content = args?.get("content") as? String
                if (content.isNullOrEmpty()) {
                    result.error("bad_args", "Missing content", null)
                    return
                }
                nfc.startWriting(uidRequirement = uid, text = content)
                result.success(null)
            }

            "cancelWriting" -> {			// OPTIONAL
                nfc.cancelWriting()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // NfcManager.Callbacks → send to Dart via same channel
    override fun onCardRead(uid: String, content: String) {
        mainHandler.post {
            channel.invokeMethod("onCardRead", mapOf(
                "uid" to uid,
                "content" to content
            ))
        }
    }

    override fun onWriteResult(success: Boolean, error: String?) {
        mainHandler.post {
            channel.invokeMethod("onWriteResult", mapOf(
                "success" to success,
                "error" to error
            ))
        }
    }

    override fun onError(message: String) {
        // You can also surface this separately if you want:
        // channel.invokeMethod("onError", mapOf("message" to message))
    }
}