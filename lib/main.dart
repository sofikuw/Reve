import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/reve_provider.dart';
import 'ui/screens/explorer_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class ReveApp extends StatelessWidget {
  const ReveApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      home: const ExplorerScreen(),
    );
  }
}
