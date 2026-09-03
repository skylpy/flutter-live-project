import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _tokenKey = 'access_token';

  String? _cachedToken;
  bool _loaded = false;

  Future<String?> readToken() async {
    if (_loaded) return _cachedToken;
    final preferences = await SharedPreferences.getInstance();
    _cachedToken = preferences.getString(_tokenKey);
    _loaded = true;
    return _cachedToken;
  }

  Future<void> saveToken(String token) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, token);
    _cachedToken = token;
    _loaded = true;
  }

  Future<void> clearToken() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    _cachedToken = null;
    _loaded = true;
  }
}
