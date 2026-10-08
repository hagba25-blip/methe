import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

/// Client du backend Python : ajoute le jeton Supabase à chaque requête.
/// Le frontend n'effectue AUCUN calcul financier ; il affiche ce que renvoie le serveur.
class ApiClient {
  ApiClient(this._supabase, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final SupabaseClient _supabase;
  final http.Client _http;

  Map<String, String> get _headers {
    final token = _supabase.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> get(String path) async {
    final res = await _http.get(Uri.parse('${Env.apiBaseUrl}$path'), headers: _headers);
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {String? idempotencyKey}) async {
    final res = await _http.post(
      Uri.parse('${Env.apiBaseUrl}$path'),
      headers: {..._headers, if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey},
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final res = await _http.patch(Uri.parse('${Env.apiBaseUrl}$path'), headers: _headers, body: jsonEncode(body));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final detail = body is Map && body['detail'] is String
          ? body['detail'] as String
          : res.statusCode == 422
              ? 'Données invalides'
              : 'Erreur ${res.statusCode}';
      throw ApiException(res.statusCode, detail);
    }
    return body as Map<String, dynamic>;
  }
}
