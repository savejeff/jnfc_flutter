import Flutter
import UIKit

public class JnfcFlutterPlugin: NSObject, FlutterPlugin {
	private var channel: FlutterMethodChannel!

	public static func register(with registrar: FlutterPluginRegistrar) {
		let channel = FlutterMethodChannel(name: "jnfc_flutter", binaryMessenger: registrar.messenger())
		let instance = JnfcFlutterPlugin(channel: channel)
		registrar.addMethodCallDelegate(instance, channel: channel)
	}

	// Custom init to store the channel for invoking callbacks to Dart
	init(channel: FlutterMethodChannel) {
		self.channel = channel
		super.init()
	}

	public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
		switch call.method {
		case "getPlatformVersion":
			result("iOS \(UIDevice.current.systemVersion)")

		case "startReading":
			// MOCK: send a fake card after 1s via the same MethodChannel
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
				guard let self = self else { return }
				let data: [String: Any] = [
					"uid": "FE:ED:FA:CE",
					"content": "Hello from iOS mock"
				]
				self.channel.invokeMethod("onCardRead", arguments: data)
			}
			result(nil)

		case "stopReading":
			// MOCK: no-op
			result(nil)

		case "startWriting":
			guard
				let args = call.arguments as? [String: Any],
				let _ = args["uid"] as? String,
				let _ = args["content"] as? String
			else {
				result(FlutterError(code: "bad_args", message: "Missing uid/content", details: nil))
				return
			}

			// MOCK: simulate success after 0.8s and callback via the same MethodChannel
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
				guard let self = self else { return }
				let response: [String: Any?] = [
					"success": true,
					"error": nil
				]
				self.channel.invokeMethod("onWriteResult", arguments: response)
			}
			result(nil)

		default:
			result(FlutterMethodNotImplemented)
		}
	}
}
