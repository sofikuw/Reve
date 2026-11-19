import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/reve_provider.dart';
import 'services/dns_fallback.dart';
import 'ui/screens/explorer_screen.dart';
import 'ui/screens/lock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installDnsFallback();
  await Hive.initFlutter(kIsWeb ? null : 'reve');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ReveProvider()),
      ],
      child: const ReveApp(),
    ),
  );
}

/// Routed through the app-lock gate when the user has set a PIN. The PIN is
/// only consulted on resume — a short background trip does not re-ask.
class ReveApp extends StatefulWidget {
  const ReveApp({super.key});

  @override
  State<ReveApp> createState() => _ReveAppState();
}

class _ReveAppState extends State<ReveApp> with WidgetsBindingObserver {
  bool _locked = false;
  int? _pausedAtMs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAtMs = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final pausedMs = _pausedAtMs;
    _pausedAtMs = null;
    final provider = context.read<ReveProvider>();
    if (!provider.isLocked) return;
    final stale =
        pausedMs == null || DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(pausedMs)) >= const Duration(minutes: 1);
    if (stale) setState(() => _locked = true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    return MaterialApp(
      title: 'reve — GitHub cloud storage',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B3FD6),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B3FD6),
          brightness: Brightness.dark,
          surface: const Color(0xFF101014),
        ),
      ),
      home: _locked
          ? LockScreen(onUnlock: () => setState(() => _locked = false))
          : const ExplorerScreen(),
    );
  }
}
