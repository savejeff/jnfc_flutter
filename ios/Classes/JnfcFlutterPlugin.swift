import Flutter
import UIKit

import Foundation
import CoreNFC

/// Handles CoreNFC read/write flows and reports back via closures.
/// Uses NFCTagReaderSession so we can read UID and NDEF (and write NDEF).
final class NfcManager: NSObject, NFCTagReaderSessionDelegate {
	// MARK: - Public callbacks
	var onCardRead: ((String, String) -> Void)?					// (uidHex, contentString)
	var onWriteResult: ((Bool, String?) -> Void)?				// (success, error)

	// MARK: - Internal state
	private var session: NFCTagReaderSession?
	private var expectedUid: String?
	private var pendingWriteText: String?

	// MARK: - Public API
	func startReading() {
		guard NFCTagReaderSession.readingAvailable else {
			onWriteResult?(false, "NFC not available on this device")
			return
		}
		expectedUid = nil
		pendingWriteText = nil
		let s = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: nil)
		s?.alertMessage = "Hold your tag near the phone."
		self.session = s!
		s!.begin()
	}

	/// Begin a write session: waits for a tag whose UID matches `uidRequirement` (if provided),
	/// then writes a single NDEF Text record containing `text`.
	func startWriting(uidRequirement: String?, text: String) {
		guard NFCTagReaderSession.readingAvailable else {
			onWriteResult?(false, "NFC not available on this device")
			return
		}
		expectedUid = uidRequirement?.uppercased()
		pendingWriteText = text
		let s = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: nil)
		s?.alertMessage = "Hold your tag near the phone to write data."
		self.session = s
		s?.begin()
	}

	func stop() {
		session?.invalidate()
		session = nil
		expectedUid = nil
		pendingWriteText = nil
	}

	// MARK: - NFCTagReaderSessionDelegate
	func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
		// no-op (but useful for logging)
	}

	func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
		// Reset state on invalidation
		self.session = nil
		self.expectedUid = nil
		self.pendingWriteText = nil
	}

	func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
		guard let tag = tags.first else { return }

		// connect
		session.connect(to: tag) { [weak self] err in
			guard let self = self else { return }
			if let err = err {
				session.invalidate(errorMessage: "Connect failed: \(err.localizedDescription)")
				return
			}

			// Resolve UID
			let uidHex = self.hexUID(for: tag)

			// If a specific UID is required for writing, verify it
			if let expected = self.expectedUid, !expected.isEmpty {
				if uidHex.uppercased() != expected {
					// Show mismatch and keep session alive to try another tag
					session.alertMessage = "Wrong tag. Expected UID \(expected), got \(uidHex). Try again."
					// iOS doesn't provide a "re-poll immediately" API here; user can re-present the right card.
					return
				}
			}

			// If we have a pending write, do write flow
			if let textToWrite = self.pendingWriteText {
				self.performWriteFlow(session: session, tag: tag, uidHex: uidHex, textToWrite: textToWrite)
				return
			}

			// Otherwise, read flow
			self.performReadFlow(session: session, tag: tag, uidHex: uidHex)
		}
	}

	// MARK: - Read / Write flows
	private func performReadFlow(session: NFCTagReaderSession, tag: NFCTag, uidHex: String) {
		guard let ndefTag = self.asNdef(tag) else {
			self.onCardRead?(uidHex, "<no NDEF support>")
			session.alertMessage = "UID: \(uidHex)"
			session.invalidate()
			return
		}

		ndefTag.readNDEF { [weak self] message, error in
			guard let self = self else { return }
			if let error = error {
				session.invalidate(errorMessage: "Read failed: \(error.localizedDescription)")
				return
			}
			let text = self.firstText(from: message) ?? "<no text>"
			self.onCardRead?(uidHex, text)
			session.alertMessage = "UID: \(uidHex)\nText: \(text)"
			session.invalidate()
		}
	}

	private func performWriteFlow(session: NFCTagReaderSession, tag: NFCTag, uidHex: String, textToWrite: String) {
		guard let ndefTag = self.asNdef(tag) else {
			self.onWriteResult?(false, "Tag does not support NDEF")
			session.invalidate(errorMessage: "Tag does not support NDEF")
			self.pendingWriteText = nil
			return
		}

		ndefTag.queryNDEFStatus { [weak self] (status, capacity, error) in
			guard let self = self else { return }
			if let error = error {
				session.invalidate(errorMessage: "NDEF status error: \(error.localizedDescription)")
				self.onWriteResult?(false, "NDEF status error: \(error.localizedDescription)")
				self.pendingWriteText = nil
				return
			}

			switch status {
			case .notSupported:
				session.invalidate(errorMessage: "NDEF not supported")
				self.onWriteResult?(false, "NDEF not supported")
				self.pendingWriteText = nil
				return
			case .readOnly:
				session.invalidate(errorMessage: "Tag is read-only")
				self.onWriteResult?(false, "Tag is read-only")
				self.pendingWriteText = nil
				return
			case .readWrite:
				let message = self.makeTextMessagePayload(text: textToWrite, language: Locale.current.languageCode ?? "en")
				let size = message.length
				if capacity < size {
					session.invalidate(errorMessage: "Not enough space (need \(size), have \(capacity))")
					self.onWriteResult?(false, "Not enough space")
					self.pendingWriteText = nil
					return
				}

				ndefTag.writeNDEF(message) { [weak self] writeError in
					guard let self = self else { return }
					if let writeError = writeError {
						session.invalidate(errorMessage: "Write failed: \(writeError.localizedDescription)")
						self.onWriteResult?(false, "Write failed: \(writeError.localizedDescription)")
						self.pendingWriteText = nil
						return
					}

					// optional: read-back confirm
					ndefTag.readNDEF { [weak self] readMessage, readError in
						guard let self = self else { return }
						if let readError = readError {
							session.alertMessage = "Write successful (verify read failed)"
							session.invalidate(errorMessage: "Verify failed: \(readError.localizedDescription)")
							self.onWriteResult?(true, nil)	// treat as success; content verification failed only
							self.pendingWriteText = nil
							return
						}
						let txt = self.firstText(from: readMessage) ?? "<no text>"
						session.alertMessage = "Write successful"
						session.invalidate()
						self.onCardRead?(uidHex, txt)		// also surface the read result for convenience
						self.onWriteResult?(true, nil)
						self.pendingWriteText = nil
					}
				}
			@unknown default:
				session.invalidate(errorMessage: "Unknown NDEF status")
				self.onWriteResult?(false, "Unknown NDEF status")
				self.pendingWriteText = nil
				return
			}
		}
	}

	// MARK: - Helpers
	private func asNdef(_ tag: NFCTag) -> NFCNDEFTag? {
		switch tag {
		case .miFare(let t):	return t as? NFCNDEFTag
		case .iso15693(let t):	return t as? NFCNDEFTag
		case .feliCa(let t):	return t as? NFCNDEFTag
		case .iso7816(let t):	return t as? NFCNDEFTag
		@unknown default:		return nil
		}
	}

	private func hexUID(for tag: NFCTag) -> String {
		let data: Data?
		switch tag {
		case .miFare(let m):	data = m.identifier
		case .iso15693(let v):	data = v.identifier
		case .feliCa(let f):	data = f.currentIDm
		case .iso7816(let iso):	data = iso.identifier
		@unknown default:		data = nil
		}
		guard let d = data else { return "<unavailable>" }
		let hex = d.map { String(format: "%02X", $0) }.joined()
		// format as "AA:BB:CC:DD"
		return stride(from: 0, to: hex.count, by: 2).map { i in
			let start = hex.index(hex.startIndex, offsetBy: i)
			let end = hex.index(start, offsetBy: 2)

			return String(hex[start..<end])
		}.joined(separator: ":")
	}

	/// Build an NFCNDEFMessage containing a single well-known Text record.
	private func makeTextMessagePayload(text: String, language: String) -> NFCNDEFMessage {
		let lang = language.data(using: .ascii) ?? Data([0x65, 0x6E]) // "en"
		let textBytes = text.data(using: .utf8) ?? Data()
		var payload = Data(capacity: 1 + lang.count + textBytes.count)
		let status: UInt8 = UInt8(lang.count & 0x3F) // UTF-8, lang length
		payload.append(status)
		payload.append(lang)
		payload.append(textBytes)

		let type = "T".data(using: .utf8)! // well-known text record type
		let record = NFCNDEFPayload(format: .nfcWellKnown, type: type, identifier: Data(), payload: payload)
		return NFCNDEFMessage(records: [record])
	}

	private func firstText(from message: NFCNDEFMessage?) -> String? {

		guard let message else { return nil }
		for record in message.records {
			let isWellKnown = record.typeNameFormat == .nfcWellKnown
			let isText = String(data: record.type, encoding: .utf8) == "T"
			if isWellKnown && isText {
				return parseText(record.payload)
			}
		}
		return nil
	}

	private func parseText(_ payload: Data) -> String {
		guard !payload.isEmpty else { return "" }
		let status = payload[0]
		let isUtf16 = (status & 0x80) != 0
		let langLen = Int(status & 0x3F)
		let textBytes = payload.dropFirst(1 + langLen)
		return isUtf16 ? (String(data: textBytes, encoding: .utf16) ?? "")
			: (String(data: textBytes, encoding: .utf8) ?? "")
	}
}


public class JnfcFlutterPlugin: NSObject, FlutterPlugin {
	private var channel: FlutterMethodChannel!
	private let nfc = NfcManager()

	public static func register(with registrar: FlutterPluginRegistrar) {
		let channel = FlutterMethodChannel(name: "jnfc_flutter", binaryMessenger: registrar.messenger())
		let instance = JnfcFlutterPlugin(channel: channel)
		registrar.addMethodCallDelegate(instance, channel: channel)
	}

	// Custom init to store the channel and hook NFC callbacks
	init(channel: FlutterMethodChannel) {
		self.channel = channel
		super.init()

		// Wire NFC callbacks → Flutter
		nfc.onCardRead = { [weak self] uid, content in
			self?.channel.invokeMethod("onCardRead", arguments: [
				"uid": uid,
				"content": content
			])
		}
		nfc.onWriteResult = { [weak self] success, error in
			self?.channel.invokeMethod("onWriteResult", arguments: [
				"success": success,
				"error": error as Any
			])
		}
	}


	public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
		switch call.method {
		case "getPlatformVersion":
			result("iOS \(UIDevice.current.systemVersion)")

		case "startReading":
			nfc.startReading()
			result(nil)

		case "stopReading":
			nfc.stop()
			result(nil)

		case "startWriting":
			guard
				let args = call.arguments as? [String: Any],
				let uid = args["uid"] as? String,
				let content = args["content"] as? String
			else {
				result(FlutterError(code: "bad_args", message: "Missing uid/content", details: nil))
				return
			}
			nfc.startWriting(uidRequirement: uid, text: content)
			result(nil)

		default:
			result(FlutterMethodNotImplemented)
		}
	}
}
