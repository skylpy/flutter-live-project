import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

/// 设置页集中承载非直播业务设置，避免 ProfilePage 变成无法维护的大文件。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.manage_accounts_outlined,
                title: '账号与安全',
              ),
              _SettingsRow(icon: Icons.notifications_none, title: '消息通知'),
              _SettingsRow(icon: Icons.lock_outline, title: '隐私设置'),
              _SettingsRow(icon: Icons.videocam_outlined, title: '直播设置'),
              _SettingsRow(icon: Icons.tune, title: '通用设置'),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.delete_outline,
                title: '清理缓存',
                trailing: '12.6 MB',
                onTap: () => _clearCache(context),
              ),
              const _SettingsRow(icon: Icons.info_outline, title: '关于我们'),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '切换主题',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            '换一种颜色，换一种心情',
            style: TextStyle(color: AppTheme.tokens(context).textSecondary),
          ),
          const SizedBox(height: 12),
          const _ThemePicker(),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => _logout(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.tokens(context).danger,
              side: BorderSide(color: AppTheme.tokens(context).danger),
            ),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理缓存？'),
        content: const Text('这只会清理本地临时数据，不会影响账号和直播内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('缓存已清理')));
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后仍然可以浏览公开直播，但互动功能需要重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
      if (context.mounted) context.pop();
    }
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1) const Divider(indent: 56, height: 1),
        ],
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    onTap:
        onTap ??
        () =>
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$title功能已预留'))),
    leading: Icon(icon),
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(color: AppTheme.tokens(context).textSecondary),
          ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  static const _labels = {
    AppThemeId.starryPurple: '星夜紫',
    AppThemeId.sweetPink: '甜美粉',
    AppThemeId.freshBlue: '清新蓝',
    AppThemeId.naturalGreen: '自然绿',
  };

  static const _colors = {
    AppThemeId.starryPurple: Color(0xFF8E5CF6),
    AppThemeId.sweetPink: Color(0xFFFF6FAE),
    AppThemeId.freshBlue: Color(0xFF58A6FF),
    AppThemeId.naturalGreen: Color(0xFF65C18C),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appThemeProvider);
    return Row(
      children: [
        for (final id in AppThemeId.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => ref.read(appThemeProvider.notifier).select(id),
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: _colors[id],
                        borderRadius: BorderRadius.circular(12),
                        border: selected == id
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: selected == id
                          ? const Center(
                              child: Icon(Icons.check, color: Colors.white),
                            )
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(_labels[id]!, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
