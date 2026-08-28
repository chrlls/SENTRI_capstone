import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Android emulators run in their own virtual network — `localhost` from
/// inside the emulator refers to the emulator itself, not the host machine
/// running the Laravel dev server (`php artisan serve`). `10.0.2.2` is the
/// emulator's documented alias for the host loopback interface (real
/// Android emulator networking behavior, not a typo). A real device or
/// production build would need a real reachable host — out of scope for
/// this MVP (docs/decisions/28-flutter-manual-sos-mvp.md).
const String kApiBaseUrl = 'http://10.0.2.2:8000';

/// Thrown for any non-2xx response. Carries the real message the backend
/// returned (per API_CONTRACTS.md) so callers never have to invent their
/// own copy of it — e.g. login's generic wrong-password/nonexistent-email
/// message must be shown verbatim, not paraphrased.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? errors;

  ApiException(this.statusCode, this.message, [this.errors]);

  @override
  String toString() => message;
}

/// Deliberately narrow — exactly the calls this MVP needs
/// (docs/decisions/28, plus incident-status polling per decision 31), not
/// a generic "everything" API service. Matches API_CONTRACTS.md's
/// request/response field names exactly.
class SentriApiClient {
  final String baseUrl;
  final http.Client _client;

  SentriApiClient({this.baseUrl = kApiBaseUrl, http.Client? client})
    : _client = client ?? http.Client();

  /// Per docs/decisions/19-account-provisioning-model.md, only civilian/
  /// responder can self-register; this MVP has no role picker
  /// (docs/decisions/28 lists exactly full_name/email/phone_number/
  /// password/agreement_accepted as the register screen's fields), so
  /// `role` is hardcoded to `civilian` here rather than exposed as input.
  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required bool agreementAccepted,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'phone_number': phoneNumber,
        'password': password,
        'role': 'civilian',
        'agreement_accepted': agreementAccepted,
      }),
    );

    final data = _decode(response.body);

    if (response.statusCode != 201) {
      throw _errorFrom(response.statusCode, data);
    }

    return data;
  }

  /// Returns the bearer token on success. Does not store it — that's
  /// AuthProvider's job, in memory only for this MVP.
  Future<String> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: _jsonHeaders(),
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = _decode(response.body);

    if (response.statusCode != 200) {
      throw _errorFrom(response.statusCode, data);
    }

    return data['token'] as String;
  }

  /// Per docs/decisions/05-manual-sos-never-gated.md, this call has zero
  /// dependency on any AI-pipeline concept — only location and the
  /// authenticated identity (via the bearer token) matter.
  Future<Map<String, dynamic>> manualSos({
    required String token,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/incidents/manual-sos'),
      headers: {..._jsonHeaders(), 'Authorization': 'Bearer $token'},
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );

    final data = _decode(response.body);

    if (response.statusCode != 201) {
      throw _errorFrom(response.statusCode, data);
    }

    return data;
  }

  /// Per API_CONTRACTS.md's `POST /api/incidents/ai-assisted-sos`:
  /// `multipart/form-data` with `latitude`, `longitude`, `audio`. Both a
  /// completed and an inconclusive `ai_classification.status` are `201`
  /// success responses (Decisions #5/#13 — AI never blocks or delays the
  /// incident) — this method returns the decoded body either way and
  /// only throws for a real non-2xx (auth/validation/insert failure).
  Future<Map<String, dynamic>> aiAssistedSos({
    required String token,
    required double latitude,
    required double longitude,
    required String audioFilePath,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/api/incidents/ai-assisted-sos'),
          )
          ..headers['Accept'] = 'application/json'
          ..headers['Authorization'] = 'Bearer $token'
          ..fields['latitude'] = latitude.toString()
          ..fields['longitude'] = longitude.toString()
          ..files.add(
            // Explicit content type: the server validates the actual file
            // bytes (PHP fileinfo), not this header, but setting it
            // correctly still avoids relying on MultipartFile.fromPath's
            // own extension-based guess.
            await http.MultipartFile.fromPath(
              'audio',
              audioFilePath,
              contentType: MediaType('audio', 'wav'),
            ),
          );

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    final data = _decode(response.body);

    if (response.statusCode != 201) {
      throw _errorFrom(response.statusCode, data);
    }

    return data;
  }

  /// Per API_CONTRACTS.md `GET /api/incidents/{incident}` — single incident
  /// detail, Decision-21 scoped. A `404` is returned both for a
  /// nonexistent id and for one the caller isn't allowed to see (a `403`
  /// would confirm an SOS exists). Used by [IncidentStatusStore]'s polling
  /// loop; the only field it currently reads is `status`.
  Future<Map<String, dynamic>> getIncident({
    required String token,
    required String incidentId,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/incidents/$incidentId'),
      headers: {..._jsonHeaders(), 'Authorization': 'Bearer $token'},
    );

    final data = _decode(response.body);

    if (response.statusCode != 200) {
      throw _errorFrom(response.statusCode, data);
    }

    return data;
  }

  Map<String, String> _jsonHeaders() => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  ApiException _errorFrom(int statusCode, Map<String, dynamic> data) {
    final message =
        data['message'] as String? ?? 'Something went wrong. Please try again.';
    final errors = data['errors'] as Map<String, dynamic>?;
    return ApiException(statusCode, message, errors);
  }
}
