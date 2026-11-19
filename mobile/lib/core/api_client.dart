import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;
  NetworkException([this.message = 'Cannot reach the RouteShield server']);
  @override
  String toString() => message;
}

class ApiClient {
  String? token;
  Map<String, String> get _h => {'Content-Type': 'application/json', if (token != null && token != 'demo') 'Authorization': 'Bearer $token'};
  Uri _u(String p, [Map<String, String>? q]) => Uri.parse('${AppConfig.apiBaseUrl}$p').replace(queryParameters: q);

  Future<dynamic> _send(Future<http.Response> Function() f) async {
    try {
      final r = await f().timeout(const Duration(seconds: 8));
      final body = r.body.isEmpty ? null : jsonDecode(r.body);
      if (r.statusCode >= 200 && r.statusCode < 300) return body;
      throw ApiException(r.statusCode, body is Map && body['error'] != null ? '${body['error']}' : 'Request failed (${r.statusCode})');
    } on SocketException {
      throw NetworkException();
    } on TimeoutException {
      throw NetworkException('The server took too long to respond');
    } on http.ClientException {
      throw NetworkException();
    } on FormatException {
      throw ApiException(500, 'Unexpected server response');
    }
  }

  Future<dynamic> get(String p, [Map<String, String>? q]) => _send(() => http.get(_u(p, q), headers: _h));
  Future<dynamic> post(String p, Map<String, dynamic> body) => _send(() => http.post(_u(p), headers: _h, body: jsonEncode(body)));
  Future<dynamic> delete(String p) => _send(() => http.delete(_u(p), headers: _h));
}
