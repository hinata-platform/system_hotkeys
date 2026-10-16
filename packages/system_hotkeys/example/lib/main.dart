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
  var _triggers = <String, String>{};
  final _presses = <String>[];
  StreamSubscription<HotKeyEvent>? _subscription;
  StreamSubscription<Map<String, String>>? _triggerSubscription;

  /// On Linux the desktop decides the keys and reports them here.
  final _external = SystemHotkeys.capabilities.configureExternally;

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
    _triggerSubscription = SystemHotkeys.triggers.listen(
      (triggers) => setState(() => _triggers = triggers),
    );
    _bind();
  }

  /// All at once: on Linux the desktop asks about the whole set in one
  /// dialog.
  Future<void> _bind() async {
    final results = await SystemHotkeys.registerAll(
      _combos,
      descriptions: {for (final id in _combos.keys) id: 'Example: $id'},
    );
    debugPrint('$results');
    if (mounted) setState(() => _results.addAll(results));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _triggerSubscription?.cancel();
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
          subtitle: Text(_external ? (_triggers[key] ?? '') : '$value'),
          trailing: Text(_results[key]?.name ?? '…'),
        ),
      if (_external)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: SystemHotkeys.configure,
            child: const Text('Configure in the system'),
          ),
        ),
      const Divider(),
      for (final press in _presses) Text(press),
    ],
  );
}
