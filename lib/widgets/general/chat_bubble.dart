import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final String message;
  final bool isStudent;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isStudent,
  });

  @override
  Widget build(BuildContext context) {
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