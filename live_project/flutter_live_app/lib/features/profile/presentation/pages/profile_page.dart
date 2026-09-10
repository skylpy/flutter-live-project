import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../controllers/profile_controller.dart';

/// 我的页面：个人资料、统计、VIP 占位和设置入口。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.tokens(context);
    final session = ref.watch(authControllerProvider).asData?.value;
    final profile = ref.watch(profileControllerProvider).asData?.value;
    final name = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : session?.user.displayName.isNotEmpty == true
        ? session!.user.displayName
        : '月亮与六便士';
    final id = profile?.username.isNotEmpty == true
        ? profile!.username
        : session?.user.username.isNotEmpty == true
        ? session!.user.username
        : '502869288';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(
              children: [
                const Text(
                  '我的',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: CircleAvatar(
                radius: 43,
                backgroundColor: tokens.secondary.withValues(alpha: 0.3),
                child: Text(
                  name.substring(0, 1),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'ID: $id · 做一个温柔且热爱生活的人 ✨',
                style: TextStyle(color: tokens.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Stat(
                  '${profile?.followingCount ?? 0}',
                  '关注',
                  onTap: () => context.push('/following'),
                ),
                _Stat('${profile?.followerCount ?? 0}', '粉丝'),
                _Stat('${profile?.likedCount ?? 0}', '获赞'),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFE7AD), Color(0xFFFFC968)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium, color: Color(0xFF8D5C20)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '开通 VIP',
                          style: TextStyle(
                            color: Color(0xFF6B461F),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '专属尊贵权益，畅享更多玩法',
                          style: TextStyle(
                            color: Color(0xFF8D6A3D),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _snack(context, 'VIP 功能准备中'),
                    child: const Text('立即开通'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                childAspectRatio: 0.95,
                padding: const EdgeInsets.symmetric(vertical: 14),
                children: [
                  _Shortcut(
                    Icons.account_balance_wallet_outlined,
                    '我的钱包',
                    onTap: () => context.push('/wallet'),
                  ),
                  const _Shortcut(Icons.emoji_events_outlined, '我的等级'),
                  const _Shortcut(Icons.people_outline, '我的粉丝'),
                  const _Shortcut(Icons.workspace_premium_outlined, '我的贵族'),
                  const _Shortcut(Icons.auto_awesome_outlined, '我的动态'),
                  const _Shortcut(Icons.history, '历史记录'),
                  const _Shortcut(Icons.star_border, '我的收藏'),
                  const _Shortcut(Icons.person_search_outlined, '我的访客'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('我的文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/files'),
            ),
            _Row(
              icon: Icons.verified_user_outlined,
              title: '实名认证',
              trailing: '未认证',
            ),
            _Row(icon: Icons.shield_outlined, title: '青少年模式'),
            _Row(icon: Icons.help_outline, title: '帮助与反馈'),
            if (session == null)
              OutlinedButton.icon(
                onPressed: () => context.push('/login'),
                icon: const Icon(Icons.login),
                label: const Text('登录后解锁更多功能'),
              ),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {this.onTap});
  final String value;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.tokens(context).textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.icon, this.label, {this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: AppTheme.tokens(context).primary),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.trailing});
  final IconData icon;
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(color: AppTheme.tokens(context).primary),
          ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right),
      ],
    ),
    onTap: () {},
  );
}
