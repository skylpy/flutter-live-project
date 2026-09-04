import 'package:shared_preferences/shared_preferences.dart';

/// 登录 Token 的本地存储。
///
/// 当前使用 SharedPreferences 便于开发；生产环境可替换为 Keychain/Keystore，
/// 上层 ApiClient 的调用方式不需要变化。
class TokenStorage {
  static const _tokenKey = 'access_token';

  String? _cachedToken;
  bool _loaded = false;

  Future<String?> readToken() async {
    // _loaded 用来区分“还没读过磁盘”和“已确认磁盘里没有 Token”。
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
