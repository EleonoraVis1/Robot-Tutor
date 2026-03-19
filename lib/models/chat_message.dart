import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String from;       // 'student' or 'system' or 'robot'
  final String message;
  final DateTime createdAt;
  final String studentUid; // Added
  final String moduleId;   // Added

  ChatMessage({
    required this.id,
    required this.from,
    required this.message,
    required this.createdAt,
    required this.studentUid,
    required this.moduleId,
  });

  // Factory to create from Firestore doc
  factory ChatMessage.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    required String studentUid,
    required String moduleId,
  }) {
    return ChatMessage(
      id: id,
      from: data['from'] ?? 'unknown',
      message: data['message'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      studentUid: studentUid,
      moduleId: moduleId,
    );
  }

  // Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'from': from,
      'message': message,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}