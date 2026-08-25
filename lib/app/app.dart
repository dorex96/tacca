import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

/// Widget radice: configura `MaterialApp.router`, tema e localizzazione.
class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router = createRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: kDebugMode,
      // Un tema solo: il restyling ha una palette sola (vedi AppTheme). Il
      // blocco su ThemeMode.light serve a non mostrare, su un telefono in
      // dark mode, un'interfaccia che nessuno ha disegnato.
      theme: AppTheme.theme,
      themeMode: ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
