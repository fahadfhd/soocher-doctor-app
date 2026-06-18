import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/stream_config.dart';

/// Holds all data needed to join a Stream video call.
class VideoCallData {
  final String streamCallId;
  final String streamToken;
  final String patientName;
  final List<String> memberIds;

  const VideoCallData({
    required this.streamCallId,
    required this.streamToken,
    required this.patientName,
    required this.memberIds,
  });
}

class VideoCallService {
  // Sanitize Firebase UID to match the web app's sanitizeId() function
  static String sanitizeId(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

  /// Fetch consultation document from Firestore REST API using the
  /// Firebase ID token obtained from the WebView's IndexedDB.
  static Future<Map<String, dynamic>> _fetchConsultation(
    String consultationId,
    String idToken,
  ) async {
    final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/${StreamConfig.firestoreProject}'
      '/databases/(default)/documents/Consultations/$consultationId'
      '?key=${StreamConfig.firestoreApiKey}',
    );
    final res = await http.get(
      url,
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (res.statusCode != 200) {
      throw Exception('Firestore fetch failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Extract a String field from a Firestore REST API document.
  /// Handles nested maps by traversing through mapValue.fields at each level.
  static String? _getString(Map<String, dynamic> doc, List<String> path) {
    dynamic node = doc['fields'];
    for (int i = 0; i < path.length; i++) {
      if (node == null) return null;
      final field = (node as Map<String, dynamic>)[path[i]];
      if (field == null) return null;
      if (i < path.length - 1) {
        // Intermediate key — descend into mapValue.fields
        node = (field['mapValue'] as Map<String, dynamic>?)?['fields'];
      } else {
        return field['stringValue'] as String?;
      }
    }
    return null;
  }

  /// Extract an Array<String> field from a Firestore REST API document.
  /// Handles nested maps by traversing through mapValue.fields at each level.
  static List<String> _getStringArray(
      Map<String, dynamic> doc, List<String> path) {
    dynamic node = doc['fields'];
    for (int i = 0; i < path.length; i++) {
      if (node == null) return [];
      final field = (node as Map<String, dynamic>)[path[i]];
      if (field == null) return [];
      if (i < path.length - 1) {
        node = (field['mapValue'] as Map<String, dynamic>?)?['fields'];
      } else {
        final values = (field['arrayValue'] as Map<String, dynamic>?)?['values'] as List?;
        if (values == null) return [];
        return values
            .map((v) => (v as Map<String, dynamic>)['stringValue'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  /// Fetch a Stream video token from the backend.
  static Future<String> _fetchStreamToken(String sanitizedUid) async {
    Future<String> tryUrl(String url) async {
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': sanitizedUid}),
      );
      if (res.statusCode != 200) throw Exception('Token fetch failed (${res.statusCode})');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final token = body['token'] as String?;
      if (token == null || token.isEmpty) throw Exception('Empty token in response');
      return token;
    }

    try {
      return await tryUrl(StreamConfig.tokenEndpoint);
    } catch (_) {
      return await tryUrl(StreamConfig.tokenFallback);
    }
  }

  /// Resolve all data required to start the native video call.
  static Future<VideoCallData> resolve({
    required String uid,
    required String idToken,
    required String consultationId,
  }) async {
    final sanitizedUid = sanitizeId(uid);

    // Run Firestore fetch and Stream token fetch in parallel
    final results = await Future.wait([
      _fetchConsultation(consultationId, idToken),
      _fetchStreamToken(sanitizedUid),
    ]);

    final doc = results[0] as Map<String, dynamic>;
    final streamToken = results[1] as String;

    final streamCallId = _getString(doc, ['extras', 'streamCallId']);
    if (streamCallId == null || streamCallId.isEmpty) {
      throw Exception('No streamCallId found for consultation $consultationId');
    }

    final patientName =
        _getString(doc, ['extras', 'patientDetails', 'patientName']) ??
            'Patient';

    final rawMembers = _getStringArray(doc, ['participants']);
    final memberIds = rawMembers.map(sanitizeId).toList();
    // Make sure the doctor is in the members list
    if (!memberIds.contains(sanitizedUid)) memberIds.add(sanitizedUid);

    return VideoCallData(
      streamCallId: streamCallId,
      streamToken: streamToken,
      patientName: patientName,
      memberIds: memberIds,
    );
  }
}
