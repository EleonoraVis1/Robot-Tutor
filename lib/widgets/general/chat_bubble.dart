import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final String message;
  final String from;

  const ChatBubble({
    super.key,
    required this.message,
    required this.from,
  });

  @override
  Widget build(BuildContext context) {
    final sender = from.toLowerCase().trim();

    if (sender == 'system' && message.toLowerCase().trim() == 'start quiz') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Expanded(child: Divider(thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Expanded(child: Divider(thickness: 1)),
          ],
        ),
      );
    }

    final isStudent = sender == 'student';

    final alignment =
        isStudent ? Alignment.centerRight : Alignment.centerLeft;

    final color =
        isStudent ? Colors.blue[400] : Colors.grey[300];

    final textColor =
        isStudent ? Colors.white : Colors.black87;

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          message,
          style: TextStyle(color: textColor),
        ),
      ),
    );
  }
}