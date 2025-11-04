import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'jnfc_flutter_platform_interface.dart';

/// An implementation of [JnfcFlutterPlatform] that uses method channels.
class MethodChannelJnfcFlutter extends JnfcFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('jnfc_flutter');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
