import 'package:flutter/material.dart';

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
