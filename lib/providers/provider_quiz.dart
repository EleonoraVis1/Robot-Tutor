import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/models/quiz_question.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final moduleQuestionsProvider = FutureProvider.family<List<QuizQuestion>, String>((ref, moduleId) async {
  final moduleRef = FirebaseFirestore.instance.collection('modules').doc(moduleId);
  final doc = await moduleRef.get();

  if (!doc.exists) return [];

  final data = doc.data();
  if (data == null) return [];

  final independentQuestions = (data['quiz_questions']?['guided'] as List<dynamic>?) ?? [];

  return independentQuestions.map((q) {
    final questionMap = q as Map<String, dynamic>;
    final options = List<String>.from(questionMap['options'] ?? []);
    final answer = questionMap['answer']?.toString() ?? '';
    final correctIndex = options.indexOf(answer);

    return QuizQuestion(
      id: questionMap['prompt'] ?? '', 
      question: questionMap['prompt'] ?? '',
      options: options,
      correctIndex: correctIndex >= 0 ? correctIndex : 0,
    );
  }).toList();
});

final quizProvider = FutureProvider.family<List<QuizQuestion>, String>((ref, moduleId) async {
  final moduleRef = FirebaseFirestore.instance.collection('modules').doc(moduleId);
  final doc = await moduleRef.get();

  if (!doc.exists) return [];

  final data = doc.data();
  if (data == null) return [];

  final independentQuestions = (data['quiz_questions']?['independent'] as List<dynamic>?) ?? [];

  return independentQuestions.map((q) {
    final questionMap = q as Map<String, dynamic>;
    final options = List<String>.from(questionMap['options'] ?? []);
    final answer = questionMap['answer']?.toString() ?? '';
    final correctIndex = options.indexOf(answer);

    return QuizQuestion(
      id: questionMap['prompt'] ?? '', 
      question: questionMap['prompt'] ?? '',
      options: options,
      correctIndex: correctIndex >= 0 ? correctIndex : 0,
    );
  }).toList();
});

final quizStartProvider = StreamProvider.family<bool, ({
  String studentId,
  String moduleId,
})>((ref, params) {
  final messagesRef = FirebaseFirestore.instance
      .collection('user_profiles')
      .doc(params.studentId)
      .collection('modules')
      .doc(params.moduleId)
      .collection('messages');

  return messagesRef.snapshots().map((snapshot) {
    for (var doc in snapshot.docs) {
      final data = doc.data();

      if (data['from'] == 'system' &&
          data['message'].toString().toLowerCase().trim() == 'start quiz') {
        return true;
      }
    }
    return false;
  });
});

final quizStatusProvider =
    StreamProvider.family<String, ({String studentId, String moduleId})>(
  (ref, params) {
    final moduleRef = FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(params.studentId)
        .collection('modules')
        .doc(params.moduleId);

    return moduleRef.snapshots().map((doc) {
      if (!doc.exists) return 'unaccessible'; 
      final data = doc.data();
      return data?['quiz_status']?.toString() ?? 'unaccessible';
    });
  },
);