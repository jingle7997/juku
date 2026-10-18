import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/prefs.dart';
import 'core/theme.dart';
import 'screens/connect_screen.dart';
import 'screens/shell_screen.dart';
import 'state/app_state.dart';

class JukuApp extends StatelessWidget {
  const JukuApp({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState(prefs)..bootstrap(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: '短剧库',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(AppPalette.light, Brightness.light),
            darkTheme: buildTheme(AppPalette.dark, Brightness.dark),
            themeMode: state.resolvedTheme,
            home: state.connected ? const ShellScreen() : const ConnectScreen(),
          );
        },
      ),
    );
  }
}
