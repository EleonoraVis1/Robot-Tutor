import 'package:csc322_starter_app/screens/general/students/screen_module.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SubjectCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String routeName;

  const SubjectCard({required this.title, required this.icon, required this.routeName});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          context.push(routeName);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.blueGrey[700]),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}