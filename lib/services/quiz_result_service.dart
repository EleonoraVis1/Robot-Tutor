import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QuizResultService {
  static Future<void> saveResult({
    required String subjectId,
    required String moduleId,
    required int score,
    required int totalQuestions,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(user.uid)
        .collection('module_results')
        .doc(moduleId);

    await ref.set({
      'subjectId': subjectId,
      'score': score,
      'totalQuestions': totalQuestions,
      'correctAnswers': score,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }
}