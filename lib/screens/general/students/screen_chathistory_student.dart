import 'package:csc322_starter_app/providers/provider_messages.dart';
import 'package:csc322_starter_app/widgets/general/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ScreenChathistorySupervisor extends ConsumerWidget {
  static const routeName = '/chat_history_student';

  final String studentUid;

  const ScreenChathistorySupervisor({
    super.key,
    required this.studentUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(chatMessagesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tutor Chat')),
      body: messagesAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Error: $e')),
        data: (messages) => ListView(
          padding: const EdgeInsets.all(16),
          children: messages
              .map(
                (msg) => ChatBubble(
                  message: msg.message,
                  isStudent: msg.from == 'student',
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}