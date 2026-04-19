import 'package:csc322_starter_app/providers/provider_students.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ScreenNotifications extends ConsumerWidget {
  static const routeName = '/notifications';

  const ScreenNotifications({super.key});

  Future<void> _markAsRead(String notifId, String uid) async {
    await FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(uid)
        .collection('notifications')
        .doc(notifId)
        .update({'read': true});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(child: Text('No notifications'));
          }

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final n = notifications[index];
              final isRead = n['read'] == true;

              return ListTile(
                leading: Icon(
                  n['type'] == 'quiz'
                      ? Icons.quiz
                      : (n['status'] == 'Accepted'
                          ? Icons.check_circle
                          : Icons.cancel),
                  color: n['type'] == 'quiz'
                      ? Colors.blue
                      : (n['status'] == 'Accepted'
                          ? Colors.green
                          : Colors.red),
                ),
                title: Builder(
                  builder: (_) {
                    final type = n['type'];

                    if (type == 'quiz') {
                      final student = n['studentName'] ?? 'Student';
                      final status = n['status'] ?? '';
                      final subject = n['subject'] ?? '';
                      final grade = n['grade'] != null ? 'Grade ${n['grade']}' : '';
                      final chapter = n['chapter'] != null ? 'Chapter ${n['chapter']}' : '';
                      final module = n['moduleId'] ?? '';

                      final action =
                          status == 'retook' ? 'retook' : 'completed';

                      return Text(
                        '$student $action $grade $subject – $chapter: $module',
                      );
                    }

                    return Text(
                      '${n['studentName']} ${n['status'].toLowerCase()} your invite',
                    );
                  },
                ),
                subtitle: Text(
                  n['timestamp'] != null
                      ? DateFormat('yyyy-MM-dd HH:mm:ss')
                          .format(n['timestamp'].toDate())
                      : '',
                ),
                tileColor: isRead ? null : Colors.blue.withOpacity(0.05),
                onTap: () {
                  _markAsRead(n['id'], FirebaseAuth.instance.currentUser!.uid);
                },
              );
            },
          );
        },
      ),
    );
  }
}