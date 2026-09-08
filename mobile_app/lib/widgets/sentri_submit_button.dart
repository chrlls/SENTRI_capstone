import 'package:flutter/material.dart';

/// A full-width `FilledButton` that swaps its label for a spinner while
/// [loading] — the exact pattern `login_screen.dart` and
/// `register_screen.dart` each hand-wrote independently, byte for byte.
/// Color/shape/height come entirely from the app-wide `filledButtonTheme`;
/// this only supplies the loading-state behaviour.
///
/// The spinner is explicitly white rather than left to inherit
/// [ProgressIndicatorThemeData]'s default color — that default is the
/// app's non-emergency accent (Cosmos Blue), which would render an
/// invisible blue spinner on this button's own blue fill.
class SentriSubmitButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const SentriSubmitButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}
