import 'package:flutter/material.dart';

/// 开播入口占位页。
///
/// 当前按钮不启动摄像头或推流，后续应接入独立的推流引擎和权限流程。
class CreateLivePage extends StatelessWidget {
  const CreateLivePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('开播')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '我要开播',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () {}, child: const Text('开始直播')),
          ],
        ),
      ),
    );
  }
}
