import 'jnfc_flutter_platform_interface.dart';

import 'dart:async';
import 'package:flutter/services.dart';

class JnfcFlutter {
  Future<String?> getPlatformVersion() {
    return JnfcFlutterPlatform.instance.getPlatformVersion();
  }
}

/// Simple model for a discovered NFC card.
class NfcCard {
  final String uid;
  final String content; // as String (e.g., NDEF text you parse/format yourself)

  NfcCard({required this.uid, required this.content});

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'content': content,
  };

  static NfcCard fromJson(Map<dynamic, dynamic> json) {
    return NfcCard(
      uid: json['uid'] as String,
      content: json['content'] as String,
    );
  }
}

class NfcWriteResult {
  final bool success;
  final String? error;

  NfcWriteResult({required this.success, this.error});
}

/// Public API surface that talks to native via a single MethodChannel.
/// Native side pushes async callbacks using channel.invokeMethod("onCardRead"/"onWriteResult", ...).
class NfcIo {
  NfcIo._() {
    _methods.setMethodCallHandler(_handleNativeCallback);
  }
  static final NfcIo instance = NfcIo._();

  static const MethodChannel _methods = MethodChannel('jnfc_flutter');

  final StreamController<NfcCard> _cardController = StreamController<NfcCard>.broadcast();

  Completer<NfcWriteResult>? _pendingWrite; // NOTE: one write at a time in this simple mock.

  /// Start a reading process.
  Future<void> startReading() async {
    await _methods.invokeMethod('startReading');
  }

  /// Stop a reading process.
  Future<void> stopReading() async {
    await _methods.invokeMethod('stopReading');
  }

  /// Stream of discovered cards (one event per card).
  Stream<NfcCard> get onCardDiscovered => _cardController.stream;

  /// Start a writing process: when a card with [uid] is presented,
  /// write [content] (String). Completes when native reports success or error.
  Future<NfcWriteResult> startWriting({
    required String uid,
    required String content,
  }) async {
    // Enforce single in-flight write for now (matches the mock implementation).
    if (_pendingWrite != null && !_pendingWrite!.isCompleted) {
      return Future.value(NfcWriteResult(success: false, error: 'write_in_progress'));
    }

    final completer = Completer<NfcWriteResult>();
    _pendingWrite = completer;

    try {
      await _methods.invokeMethod('startWriting', {
        'uid': uid,
        'content': content,
      });
    } on PlatformException catch (e) {
      if (!completer.isCompleted) {
        completer.complete(NfcWriteResult(success: false, error: e.message ?? 'platform_error'));
      }
    }

    return completer.future;
  }

  /// Handle native -> Dart callbacks sent via the same MethodChannel.
  Future<void> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onCardRead': {
        final map = (call.arguments as Map<dynamic, dynamic>);
        final card = NfcCard.fromJson(map);
        _cardController.add(card);
        break;
      }
      case 'onWriteResult': {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final success = (args?['success'] as bool?) ?? false;
        final error = args?['error'] as String?;
        final res = NfcWriteResult(success: success, error: error);
        final c = _pendingWrite;
        _pendingWrite = null;
        c?.complete(res);
        break;
      }
      default:
      // Unknown callback; ignore or log as needed.
        break;
    }
  }

  /// Dispose resources if your app/plugin needs manual teardown.
  void dispose() {
    _cardController.close();
  }
}
