import 'package:flutter/foundation.dart';

import '../services/sentri_api_client.dart';

enum AuthStatus { unauthenticated, working, authenticated }

/// docs/decisions/28-flutter-manual-sos-mvp.md: token is in-memory only —
/// no flutter_secure_storage or persistence in this MVP. A real, tracked
/// gap (restart = logged out), not an oversight.
class AuthProvider extends ChangeNotifier {
  final SentriApiClient apiClient;

  AuthProvider({SentriApiClient? apiClient}) : apiClient = apiClient ?? SentriApiClient();

  AuthStatus _status = AuthStatus.unauthenticated;
  String? _token;
  String? _errorMessage;

  AuthStatus get status => _status;
  String? get token => _token;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isWorking => _status == AuthStatus.working;

  /// Per API_CONTRACTS.md, registration never issues a token — this never
  /// sets `_token` or `_status = authenticated`, matching the backend's
  /// own register/login separation.
  Future<bool> register({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required bool agreementAccepted,
  }) async {
    _errorMessage = null;
    _status = AuthStatus.working;
    notifyListeners();

    try {
      await apiClient.register(
        fullName: fullName,
        email: email,
        phoneNumber: phoneNumber,
        password: password,
        agreementAccepted: agreementAccepted,
      );
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to reach the server. Check your connection and try again.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _errorMessage = null;
    _status = AuthStatus.working;
    notifyListeners();

    try {
      final token = await apiClient.login(email: email, password: password);
      _token = token;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to reach the server. Check your connection and try again.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }
}
