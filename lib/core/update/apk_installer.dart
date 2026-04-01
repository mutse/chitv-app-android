import 'package:flutter/services.dart';

enum ApkInstallResult { launched, permissionRequired, failed }

class ApkInstaller {
  static const MethodChannel _channel = MethodChannel('chitv/update');

  static Future<ApkInstallResult> installApk(String path) async {
    final result = await _channel.invokeMethod<String>(
      'installApk',
      <String, dynamic>{'path': path},
    );

    switch (result) {
      case 'launched':
        return ApkInstallResult.launched;
      case 'permission_required':
        return ApkInstallResult.permissionRequired;
      default:
        return ApkInstallResult.failed;
    }
  }

  static Future<void> openInstallSettings() {
    return _channel.invokeMethod<void>('openInstallSettings');
  }
}
