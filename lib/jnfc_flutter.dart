
import 'jnfc_flutter_platform_interface.dart';

import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';


class JnfcFlutter {
  Future<String?> getPlatformVersion() {
    return JnfcFlutterPlatform.instance.getPlatformVersion();
  }
}



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
  NfcIo._();
  static final NfcIo instance = NfcIo._();

  static const MethodChannel _methods = MethodChannel('jnfc_flutter');
  static const EventChannel _events = EventChannel('jnfc_flutter/events');

  Stream<NfcCard>? _cardStream;

  /// Start a reading process.
  Future<void> startReading() async {
    await _methods.invokeMethod('startReading');
  }

  /// Stop a reading process.
  Future<void> stopReading() async {
    await _methods.invokeMethod('stopReading');
  }

  /// Stream of discovered cards (one event per card).
  Stream<NfcCard> get onCardDiscovered {
    _cardStream ??= _events
        .receiveBroadcastStream()
        .map((event) {
      final map = (event as Map<dynamic, dynamic>);
      if (map['event'] == 'card') {
        return NfcCard.fromJson(map['data'] as Map<dynamic, dynamic>);
      }
      throw StateError('Unknown event: ${map['event']}');
    });
    return _cardStream!;
  }

  /// Start a writing process: when a card with [uid] is presented,
  /// write [content] (String). Returns success or error.
  Future<NfcWriteResult> startWriting({
    required String uid,
    required String content,
  }) async {
    try {
      final res = await _methods.invokeMapMethod<String, dynamic>('startWriting', {
        'uid': uid,
        'content': content,
      });
      final ok = (res?['success'] as bool?) ?? false;
      final err = res?['error'] as String?;
      return NfcWriteResult(success: ok, error: err);
    } on PlatformException catch (e) {
      return NfcWriteResult(success: false, error: e.message ?? 'platform_error');
    }
  }
}
