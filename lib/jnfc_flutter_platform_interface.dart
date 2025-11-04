import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'jnfc_flutter_method_channel.dart';

abstract class JnfcFlutterPlatform extends PlatformInterface {
  /// Constructs a JnfcFlutterPlatform.
  JnfcFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static JnfcFlutterPlatform _instance = MethodChannelJnfcFlutter();

  /// The default instance of [JnfcFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelJnfcFlutter].
  static JnfcFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [JnfcFlutterPlatform] when
  /// they register themselves.
  static set instance(JnfcFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
