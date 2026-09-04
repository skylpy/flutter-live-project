import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../controllers/auth_controller.dart';

/// 登录和注册共用的页面。
///
/// 页面只收集输入并调用 Controller；真正的网络请求和 Token 保存不放在 UI 中。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _registerMode = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    ref.listen(authControllerProvider, (previous, next) {
      if (!next.isLoading && next.hasValue && next.value != null && mounted) {
        context.go('/home');
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(_registerMode ? '注册账号' : '登录')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.live_tv, size: 72),
                const SizedBox(height: 16),
                Text(
                  'Flutter Live',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码（至少 6 位）',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_registerMode) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: '显示名称（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (authState.hasError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${authState.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: authState.isLoading ? null : _submit,
                  child: Text(_registerMode ? '注册并登录' : '登录'),
                ),
                TextButton(
                  onPressed: authState.isLoading
                      ? null
                      : () => setState(() => _registerMode = !_registerMode),
                  child: Text(_registerMode ? '已有账号？去登录' : '没有账号？去注册'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    // 根据当前模式调用同一个 AuthController 的登录或注册方法。
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (_registerMode) {
      await ref
          .read(authControllerProvider.notifier)
          .register(username, password, _displayNameController.text.trim());
    } else {
      await ref.read(authControllerProvider.notifier).login(username, password);
    }
  }
}
