import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

Query<Map<String, dynamic>> _chatQuery(String studentUid) {
  return FirebaseFirestore.instance
      .collection('conversations')
      .doc(studentUid)
      .collection('messages')
      .orderBy('createdAt', descending: false);
}

List<ChatMessage> _mapMessages(QuerySnapshot snapshot) {
  return snapshot.docs
      .map((doc) => ChatMessage.fromFirestore(
            doc.id,
            doc.data() as Map<String, dynamic>,
          ))
      .toList();
}

final chatMessagesProvider =
    StreamProvider<List<ChatMessage>>((ref) {
  final authAsync = ref.watch(authStateProvider);

  return authAsync.when(
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
    data: (user) {
      if (user == null) return const Stream.empty();

      return _chatQuery(user.uid)
          .snapshots()
          .map(_mapMessages);
    },
  );
});
final chatMessagesProviderForStudent =
    StreamProvider.family<List<ChatMessage>, String>((ref, studentUid) {
  return _chatQuery(studentUid)
      .snapshots()
      .map(_mapMessages);
});