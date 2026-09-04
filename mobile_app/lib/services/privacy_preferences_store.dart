import 'package:flutter/foundation.dart';

/// Session-only, in-memory privacy & security preferences.
///
/// Same contract as `EmergencyContactsStore` / `NotificationPreferencesStore`:
/// **not** persisted, **not** sent anywhere, reset on every app restart.
/// No privacy-preferences endpoint exists yet.
///
/// IMPORTANT: every toggle here is display-only in this pass. Nothing
/// below changes real behaviour —
/// [sharePreciseLocationWithResponders] does **not** alter what
/// `SosController` transmits (it always sends the device's GPS fix), and
/// [allowDiagnosticsReports] is inert (no diagnostics/analytics SDK is
/// wired). They exist to preview the eventual settings surface.
class PrivacyPreferencesStore extends ChangeNotifier {
  bool _sharePreciseLocationWithResponders = true;
  bool _allowDiagnosticsReports = false;

  bool get sharePreciseLocationWithResponders =>
      _sharePreciseLocationWithResponders;
  bool get allowDiagnosticsReports => _allowDiagnosticsReports;

  set sharePreciseLocationWithResponders(bool value) {
    if (_sharePreciseLocationWithResponders == value) return;
    _sharePreciseLocationWithResponders = value;
    notifyListeners();
  }

  set allowDiagnosticsReports(bool value) {
    if (_allowDiagnosticsReports == value) return;
    _allowDiagnosticsReports = value;
    notifyListeners();
  }
}
