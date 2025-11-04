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

class NfcIo {
  NfcIo._() {
    _methods.setMethodCallHandler(_handleNativeCallback);
  }
  static final NfcIo instance = NfcIo._();

  static const MethodChannel _methods = MethodChannel('jnfc_flutter');

  final StreamController<NfcCard> _cardController = StreamController.broadcast();
  Completer<NfcWriteResult>? _pendingWrite;

  Stream<NfcCard> get onCardDiscovered => _cardController.stream;

  Future<void> startReading() => _methods.invokeMethod('startReading');
  Future<void> stopReading() => _methods.invokeMethod('stopReading');

  /// OPTIONAL: explicit cancel entrypoint (no error if nothing pending)
  Future<void> cancelWriting() async {
    _pendingWrite?.complete(NfcWriteResult(success: false, error: 'canceled'));
    _pendingWrite = null;
    try {
      await _methods.invokeMethod('cancelWriting');
    } catch (_) {}
  }

  Future<NfcWriteResult> startWriting({
    required String uid,
    required String content,
  }) async {
    // override the previous pending Future
    if (_pendingWrite != null && !_pendingWrite!.isCompleted) {
      _pendingWrite!.complete(NfcWriteResult(success: false, error: 'canceled'));
    }
    final completer = Completer<NfcWriteResult>();
    _pendingWrite = completer;

    await _methods.invokeMethod('startWriting', {
      'uid': uid,
      'content': content,
    });

    return completer.future;
  }

  Future<void> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onCardRead': {
        final map = (call.arguments as Map<dynamic, dynamic>);
        final card = NfcCard.fromJson(map);
        _cardController.add(card);
        break;
      }
      case 'onWriteResult': {
        final args = (call.arguments as Map).cast<String, dynamic>();
        final res = NfcWriteResult(
          success: (args['success'] as bool?) ?? false,
          error: args['error'] as String?,
        );
        _pendingWrite?.complete(res);
        _pendingWrite = null;
        break;
      }
    }
  }

  /// Dispose resources if your app/plugin needs manual teardown.
  void dispose() {
    _cardController.close();
  }
}
