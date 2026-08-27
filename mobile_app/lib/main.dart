import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'theme/sentri_colors.dart';

void main() {
  runApp(const SentriApp());
}

/// docs/decisions/28-flutter-manual-sos-mvp.md: three screens only
/// (register, login, SOS), gated purely by in-memory AuthProvider state —
/// login/register push straight to the next screen on success, so there
/// is no separate route-guard layer to build for a flow this small.
class SentriApp extends StatelessWidget {
  const SentriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        title: 'SENTRI',
        debugShowCheckedModeBanner: false,
        // Explicit ColorScheme/component themes, not just `colorSchemeSeed`:
        // Material 3's seed-derived tonal palette picks a muted, darkened
        // tone for `primary` in light mode rather than the literal accent
        // hex (confirmed by rendering it — the seed alone produced a dull
        // brownish button, not #EB1B1D), and would also tint the AppBar's
        // surface a pale pink instead of the intended near-white. Pinning
        // these explicitly is what actually makes "red as the sole accent
        // color" true on screen, not just in the seed value.
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: SentriColors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: SentriColors.primaryRed,
            brightness: Brightness.light,
          ).copyWith(
            primary: SentriColors.primaryRed,
            onPrimary: Colors.white,
            surface: SentriColors.background,
            onSurface: SentriColors.textPrimary,
            error: SentriColors.caution,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: SentriColors.background,
            foregroundColor: SentriColors.textPrimary,
            elevation: 0,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: SentriColors.primaryRed,
              foregroundColor: Colors.white,
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: SentriColors.primaryRed),
          ),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}
