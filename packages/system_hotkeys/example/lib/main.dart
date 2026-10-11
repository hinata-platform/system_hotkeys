import 'dart:async';

import 'package:flutter/material.dart';
import 'package:system_hotkeys/system_hotkeys.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: HotkeysDemo()));
}

/// Binds two combinations and lists every press. Switch to another app and
/// press them there: the presses still arrive.
class HotkeysDemo extends StatefulWidget {
  const HotkeysDemo({super.key});

  @override
  State<HotkeysDemo> createState() => _HotkeysDemoState();
}

class _HotkeysDemoState extends State<HotkeysDemo> {
  static const _combos = {
    // Spotlight's own shortcut: the plugin answers conflict, not bound.
    'spotlight': HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: {HotKeyModifier.meta},
    ),
    'toggle': HotKey(
      key: PhysicalKeyboardKey.keyS,
      modifiers: {
        HotKeyModifier.control,
        HotKeyModifier.alt,
        HotKeyModifier.meta,
      },
    ),
    'focus': HotKey(
      key: PhysicalKeyboardKey.keyF,
      modifiers: {
        HotKeyModifier.control,
        HotKeyModifier.alt,
        HotKeyModifier.shift,
      },
    ),
  };

  final _results = <String, HotKeyResult>{};
  final _presses = <String>[];
  StreamSubscription<HotKeyEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = SystemHotkeys.events.listen((event) {
      debugPrint('pressed ${event.id}');
      setState(
        () => _presses.insert(
          0,
          '${TimeOfDay.now().format(context)}  ${event.id}',
        ),
      );
    });
    _bind();
  }

  Future<void> _bind() async {
    for (final MapEntry(:key, :value) in _combos.entries) {
      final result = await SystemHotkeys.register(key, value);
      debugPrint('$key: ${result.name}');
      if (mounted) setState(() => _results[key] = result);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    SystemHotkeys.unregisterAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      for (final MapEntry(:key, :value) in _combos.entries)
        ListTile(
          title: Text(key),
          subtitle: Text('$value'),
          trailing: Text(_results[key]?.name ?? '…'),
        ),
      const Divider(),
      for (final press in _presses) Text(press),
    ],
  );
}
