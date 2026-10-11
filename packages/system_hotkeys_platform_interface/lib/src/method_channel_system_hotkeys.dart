import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'hot_key.dart';
import 'system_hotkeys_platform.dart';

/// The implementation the macOS and Windows packages answer natively.
class MethodChannelSystemHotkeys extends SystemHotkeysPlatform {
  @visibleForTesting
  static const MethodChannel methodChannel = MethodChannel('system_hotkeys');

  @visibleForTesting
  static const EventChannel eventChannel = EventChannel(
    'system_hotkeys/events',
  );

  Stream<HotKeyEvent>? _events;

  @override
  Future<HotKeyResult> register(String id, HotKey hotKey) async {
    if (!hotKey.hasModifier || !HotKey.isSupportedKey(hotKey.key)) {
      // Released all the same: the caller asked for this id to mean something
      // else now, and it must not go on meaning the old combination.
      await unregister(id);
      return HotKeyResult.unsupported;
    }
    try {
      final result = await methodChannel.invokeMethod<String>('register', {
        'id': id,
        ...hotKey.toMap(),
      });
      return HotKeyResult.values.asNameMap()[result] ??
          HotKeyResult.unsupported;
    } on MissingPluginException {
      return HotKeyResult.unsupported;
    }
  }

  @override
  Future<void> unregister(String id) async {
    try {
      await methodChannel.invokeMethod<void>('unregister', {'id': id});
    } on MissingPluginException {
      // Nothing was ever bound on a platform without an implementation.
    }
  }

  @override
  Future<void> unregisterAll() async {
    try {
      await methodChannel.invokeMethod<void>('unregisterAll');
    } on MissingPluginException {
      // As above.
    }
  }

  @override
  Stream<HotKeyEvent> get events => _events ??= eventChannel
      .receiveBroadcastStream()
      .map((id) => HotKeyEvent(id as String));
}
