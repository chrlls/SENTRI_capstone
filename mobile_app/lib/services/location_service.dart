import 'package:geolocator/geolocator.dart';

/// A device-permission/GPS concept, not an API error — thrown by
/// [acquireCurrentLocation] instead of letting a raw platform exception
/// escape, so every caller can show the same kind of user-facing message.
class LocationUnavailableException implements Exception {
  final String message;
  LocationUnavailableException(this.message);
}

/// `--dart-define=FAIL_GPS=true` makes every caller behave like a device
/// that cannot produce a fix at all, without needing a broken device or a
/// weak-signal location to test against. Compiles to `false` in any build
/// that doesn't define it; never true in normal use. See Decision 31 §1.1.
const bool _simulateGpsFailure = bool.fromEnvironment('FAIL_GPS');

/// Acquires one device location fix, checking service-enabled and
/// permission state first. Extracted from `SosController` so the manual-SOS
/// submission path and the Home tab's ambient location card share exactly
/// one copy of this logic — both need the same real device checks, and a
/// second copy could silently drift from them.
Future<Position> acquireCurrentLocation({
  Duration timeLimit = const Duration(seconds: 12),
}) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw LocationUnavailableException(
      'Location services are turned off. Enable location and try again.',
    );
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw LocationUnavailableException(
        'Location permission denied. SENTRI needs your location to send an SOS.',
      );
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw LocationUnavailableException(
      'Location permission is permanently denied. Enable it in system settings.',
    );
  }

  try {
    if (_simulateGpsFailure) {
      // Behaves like a device that can't produce a fix at all — the real
      // catch below then runs the fallback + throw path.
      throw Exception('simulated GPS failure');
    }
    return await Geolocator.getCurrentPosition(
      // Bound the wait: without a limit `getCurrentPosition` blocks until a
      // fresh fix arrives, which can be never (weak signal, indoors). On
      // timeout, fall back to the last known fix if there is one rather
      // than failing outright.
      locationSettings: LocationSettings(timeLimit: timeLimit),
    );
  } catch (_) {
    final lastKnown =
        _simulateGpsFailure ? null : await Geolocator.getLastKnownPosition();
    if (lastKnown != null) return lastKnown;
    throw LocationUnavailableException(
      'Couldn\'t get a location fix. Move to an open area and try again.',
    );
  }
}
