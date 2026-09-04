import 'package:flutter/foundation.dart';

/// Session-only, in-memory notification-category preferences.
///
/// Deliberately **not** persisted (no `shared_preferences`, no local DB)
/// and **not** sent to any endpoint — the notification-preferences API
/// does not exist yet. This is a real, working preview of that feature
/// that resets on every app restart, on purpose — the same contract as
/// `EmergencyContactsStore`. When the endpoint lands, only these setters
/// gain a network call; the fields and their defaults stay as they are.
class NotificationPreferencesStore extends ChangeNotifier {
  bool _incidentStatusUpdates = true;
  bool _emergencyContactAlerts = true;
  bool _systemAnnouncements = false;

  bool get incidentStatusUpdates => _incidentStatusUpdates;
  bool get emergencyContactAlerts => _emergencyContactAlerts;
  bool get systemAnnouncements => _systemAnnouncements;

  set incidentStatusUpdates(bool value) {
    if (_incidentStatusUpdates == value) return;
    _incidentStatusUpdates = value;
    notifyListeners();
  }

  set emergencyContactAlerts(bool value) {
    if (_emergencyContactAlerts == value) return;
    _emergencyContactAlerts = value;
    notifyListeners();
  }

  set systemAnnouncements(bool value) {
    if (_systemAnnouncements == value) return;
    _systemAnnouncements = value;
    notifyListeners();
  }
}
