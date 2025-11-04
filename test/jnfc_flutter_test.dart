import 'package:flutter_test/flutter_test.dart';
import 'package:jnfc_flutter/jnfc_flutter.dart';
import 'package:jnfc_flutter/jnfc_flutter_platform_interface.dart';
import 'package:jnfc_flutter/jnfc_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockJnfcFlutterPlatform
    with MockPlatformInterfaceMixin
    implements JnfcFlutterPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final JnfcFlutterPlatform initialPlatform = JnfcFlutterPlatform.instance;

  test('$MethodChannelJnfcFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelJnfcFlutter>());
  });

  test('getPlatformVersion', () async {
    JnfcFlutter jnfcFlutterPlugin = JnfcFlutter();
    MockJnfcFlutterPlatform fakePlatform = MockJnfcFlutterPlatform();
    JnfcFlutterPlatform.instance = fakePlatform;

    expect(await jnfcFlutterPlugin.getPlatformVersion(), '42');
  });
}
