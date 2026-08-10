import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/slide_sos_button.dart';
import '../widgets/subscription_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ThaiGuard',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          // Выбор языка
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.language, color: Colors.white, size: 18),
            label: const Text('EN', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            SlideSosButton(
              onDispatch: () {
                // Логика вызова SOS
              },
            ),
            const Spacer(),
            SubscriptionCard(validUntil: 'Oct 24, 2026', onTap: () {}),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
