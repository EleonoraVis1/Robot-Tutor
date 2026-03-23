// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/providers/provider_quiz.dart';
import 'package:csc322_starter_app/services/quiz_result_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenQuiz extends ConsumerStatefulWidget {
  static const routeName =
      '/subject/:subjectId/module/:moduleId/quiz';

  final String? studentUid;
  final String subjectId;
  final String moduleId;
  

  const ScreenQuiz({super.key, required this.studentUid, required this.subjectId, required this.moduleId});

  @override
  ConsumerState<ScreenQuiz> createState() => _ScreenQuizState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenQuizState extends ConsumerState<ScreenQuiz> {
  // The "instance variables" managed in this state
  bool _isInit = true;

  ////////////////////////////////////////////////////////////////
  // Runs the following code once upon initialization
  ////////////////////////////////////////////////////////////////
  @override
  void didChangeDependencies() {
    if (_isInit) {
      _init();
      _isInit = false;
      super.didChangeDependencies();
    }
  }

  @override
  void initState() {
    super.initState();
  }

  ////////////////////////////////////////////////////////////////
  // Initializes state variables and resources
  ////////////////////////////////////////////////////////////////
  Future<void> _init() async {}

  int _currentIndex = 0;
  int _score = 0;
  int? _selected;
 
  @override
  Widget build(BuildContext context) {
    final params = GoRouterState.of(context).pathParameters;
    final subjectId = params['subjectId']!;
    final moduleId = params['moduleId']!;
    final profileProvider = ref.watch(providerUserProfile); 
    final uid = profileProvider.uid;

    // Watch the quiz provider (AsyncValue)
    final questionsAsync = ref.watch(quizProvider(moduleId));

    return questionsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        body: Center(child: Text('Error loading questions: $err')),
      ),
      data: (questions) {
        // Get the current question safely
        final question = questions[_currentIndex];

        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),
                Text('Question ${_currentIndex + 1} of ${questions.length}'),
                const SizedBox(height: 16),
                Text(
                  question.question,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                ...List.generate(question.options.length, (i) {
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: RadioListTile<int>(
                      value: i,
                      groupValue: _selected,
                      title: Text(question.options[i]),
                      onChanged: (v) {
                        setState(() => _selected = v);
                      },
                    ),
                  );
                }),

                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _selected == null
                              ? null
                              : () {
                                  if (_selected == question.correctIndex) {
                                    _score++;
                                  }
                                  if (_currentIndex < questions.length - 1) {
                                    setState(() {
                                      _currentIndex++;
                                      _selected = null;
                                    });
                                  } else {
                                    _saveAndShowResult(
                                      context,
                                      subjectId,
                                      moduleId,
                                      questions.length,
                                      uid,
                                    );
                                  }
                                },
                          child: Text(
                            _currentIndex < questions.length - 1
                                ? 'Next'
                                : 'Finish',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveAndShowResult(
    BuildContext context,
    String subjectId,
    String moduleId,
    int total,
    String uid,
  ) async {
    await QuizResultService.saveResult(
      subjectId: subjectId,
      moduleId: moduleId,
      score: _score,
      totalQuestions: total,
    );
    final moduleRef = FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(uid)
          .collection('modules')
          .doc(moduleId);

      await moduleRef.set({'quiz_status': 'completed'}, SetOptions(merge: true));
    _showResult(context, total);
  }

  void _showResult(BuildContext context, int total) {
        showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Quiz Complete 🎉'),
        content: Text('Score: $_score / $total'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); 
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
