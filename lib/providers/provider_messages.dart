import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';
import 'package:flutter/foundation.dart';


/// Auth state
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Helper: returns the messages query for a given student & module
Query<Map<String, dynamic>> _moduleMessagesQuery(String studentUid, String moduleId) {
  return FirebaseFirestore.instance
      .collection('user_profiles')
      .doc(studentUid)
      .collection('modules')
      .doc(moduleId)
      .collection('messages')
      .orderBy('createdAt', descending: false);
}

List<ChatMessage> _mapMessages(QuerySnapshot snapshot, String studentUid, String moduleId) {
  return snapshot.docs
      .map((doc) => ChatMessage.fromFirestore(
            doc.id,
            doc.data() as Map<String, dynamic>,
            studentUid: studentUid,
            moduleId: moduleId,
          ))
      .toList();
}

final moduleChatProvider = StreamProvider.family<List<ChatMessage>, String>((ref, moduleId) {
  final authAsync = ref.watch(authStateProvider);

  return authAsync.when(
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
    data: (user) {
      if (user == null) return const Stream.empty();
      final query = _moduleMessagesQuery(user.uid, moduleId);
      return query.snapshots().map((snap) => _mapMessages(snap, user.uid, moduleId));
    },
  );
});

final moduleChatForStudentProvider =
    StreamProvider.family<List<ChatMessage>, ({String studentUid, String moduleId})>((ref, params) {

  final query = FirebaseFirestore.instance
      .collection('user_profiles')
      .doc(params.studentUid)
      .collection('modules')
      .doc(params.moduleId)
      .collection('messages')
      .orderBy('createdAt', descending: false);

  return query.snapshots().map((snap) {
    debugPrint("Messages received: ${snap.docs.length}");

    return snap.docs.map((doc) {
      return ChatMessage.fromFirestore(
        doc.id,
        doc.data(),
        studentUid: params.studentUid,
        moduleId: params.moduleId,
      );
    }).toList();
  }).handleError((error) {
    debugPrint("Firestore error: $error");
  });
});