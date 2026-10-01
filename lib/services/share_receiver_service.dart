import 'package:flutter/services.dart';

class ShareReceiverService {
  static const _channel = MethodChannel('global_context/share_receiver');

  static void listen(void Function(String text) onText) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedText') return;
      final value = '${call.arguments ?? ''}'.trim();
      if (value.isNotEmpty) onText(value);
    });
  }

  Future<String?> takePendingText() async {
    try {
      final value = await _channel.invokeMethod<String>('takePendingShare');
      final clean = value?.trim();
      return clean == null || clean.isEmpty ? null : clean;
    } on MissingPluginException {
      return null;
    }
  }
}
