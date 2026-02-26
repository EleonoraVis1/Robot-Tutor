import 'package:csc322_starter_app/providers/provider_messages.dart';
import 'package:csc322_starter_app/widgets/general/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ScreenChathistorySupervisor extends ConsumerWidget {
  static const routeName = '/chat_history';

  final String studentUid;

  const ScreenChathistorySupervisor({
    super.key,
    required this.studentUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync =
        ref.watch(chatMessagesProviderForStudent(studentUid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat History'),
      ),
      body: messagesAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Error: $e')),
        data: (messages) {
          if (messages.isEmpty) {
            return const Center(
              child: Text('No messages yet'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];

              return ChatBubble(
                message: msg.message,
                isStudent: msg.from == 'student',
              );
            },
          );
        },
      ),
    );
  }
}