import 'package:flutter/material.dart';
import 'package:yingjian/app/navigation/app_router.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('映见', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 12),
                Text(
                  '一张精修，整组好看',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.editor);
                  },
                  child: const Text('开始修图'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
