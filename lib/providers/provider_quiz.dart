import 'package:csc322_starter_app/models/quiz_question.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


final quizProvider =
    Provider.family<List<QuizQuestion>, String>((ref, moduleId) {
  // Mock questions for now
  return [
    QuizQuestion(
      id: 'q1',
      question: 'What is 2 + 2?',
      options: ['1', '2', '3', '4'],
      correctIndex: 3,
    ),
    QuizQuestion(
      id: 'q2',
      question: 'What is 5 × 3?',
      options: ['8', '15', '10', '20'],
      correctIndex: 1,
    ),
  ];
});