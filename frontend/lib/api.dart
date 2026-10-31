import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int status;
  final String? code;
  ApiException(this.message, this.status, [this.code]);
  @override
  String toString() => message;
}

class Api {
  static const root = 'http://127.0.0.1:3000';

  /// Set by AppState when the user switches company; sent on every request.
  static int? companyId;

  static Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (companyId != null) 'x-company-id': '$companyId',
      };

  static Uri _u(String path, [Map<String, dynamic>? q]) => Uri.parse('$root/api$path')
      .replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  static dynamic _handle(http.Response r) {
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 400) {
      final msg = body is Map ? body['error'] as String? : null;
      throw ApiException(msg ?? 'Request failed (${r.statusCode})', r.statusCode, body is Map ? body['code'] as String? : null);
    }
    return body;
  }

  static Future<dynamic> _send(Future<http.Response> Function() f) async {
    try {
      return _handle(await f());
    } on SocketException {
      throw ApiException('Cannot reach the server. Start it with "npm start" in the backend folder.', 0);
    } on http.ClientException {
      throw ApiException('Cannot reach the server. Start it with "npm start" in the backend folder.', 0);
    }
  }

  /// Binary download (Excel exports).
  static Future<Uint8List> getBytes(String path, [Map<String, dynamic>? q]) async {
    try {
      final r = await http.get(_u(path, q), headers: _headers);
      if (r.statusCode >= 400) {
        String? msg;
        try {
          msg = (jsonDecode(r.body) as Map)['error'] as String?;
        } catch (_) {}
        throw ApiException(msg ?? 'Download failed (${r.statusCode})', r.statusCode);
      }
      return r.bodyBytes;
    } on SocketException {
      throw ApiException('Cannot reach the server. Start it with "npm start" in the backend folder.', 0);
    } on http.ClientException {
      throw ApiException('Cannot reach the server. Start it with "npm start" in the backend folder.', 0);
    }
  }

  static Future<dynamic> get(String path, [Map<String, dynamic>? q]) => _send(() => http.get(_u(path, q), headers: _headers));
  static Future<dynamic> post(String path, Object body) => _send(() => http.post(_u(path), headers: _headers, body: jsonEncode(body)));
  static Future<dynamic> put(String path, Object body) => _send(() => http.put(_u(path), headers: _headers, body: jsonEncode(body)));
  static Future<dynamic> delete(String path, [Map<String, dynamic>? q]) => _send(() => http.delete(_u(path, q), headers: _headers));
}
