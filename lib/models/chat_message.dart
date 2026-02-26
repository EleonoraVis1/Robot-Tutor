import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String from; 
  final String message;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.from,
    required this.message,
    required this.createdAt,
  });

  factory ChatMessage.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return ChatMessage(
      id: id,
      from: data['from'] as String,
      message: data['message'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }
}