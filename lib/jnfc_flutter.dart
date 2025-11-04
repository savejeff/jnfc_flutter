
import 'jnfc_flutter_platform_interface.dart';

class JnfcFlutter {
  Future<String?> getPlatformVersion() {
    return JnfcFlutterPlatform.instance.getPlatformVersion();
  }
}
