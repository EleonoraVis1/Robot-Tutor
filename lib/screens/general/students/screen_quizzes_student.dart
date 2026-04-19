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
  final int grade;
  

  const ScreenQuiz({super.key, required this.studentUid, required this.subjectId, required this.grade, required this.moduleId});

  @override
  ConsumerState<ScreenQuiz> createState() => _ScreenQuizState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenQuizState extends ConsumerState<ScreenQuiz> {
  // The "instance variables" managed in this state
  bool _isInit = true;
  bool _increase = true;

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

  int extractChapterFromId(String id) {
    final match = RegExp(r'ch(\d+)').firstMatch(id);
    return match != null ? int.parse(match.group(1)!) : 0;
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
    await _notifySupervisors(
      uid: uid,
      subjectId: subjectId,
      moduleId: moduleId,
      grade: widget.grade, 
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

  Future<void> _notifySupervisors({
    required String uid,
    required String subjectId,
    required String moduleId,
    required int grade,
  }) async {
    final firestore = FirebaseFirestore.instance;

    final userDoc =
        await firestore.collection('user_profiles').doc(uid).get();

    final userData = userDoc.data();
    final firstName = userData?['first_name'] ?? 'Name';
    final lastName = userData?['last_name'] ?? 'Lastname';
    final studentName = firstName + ' ' + lastName;

    final moduleDoc = await firestore
        .collection('modules')
        .doc(moduleId)
        .get();

    final moduleTitle = moduleDoc.data()?['title'] ?? moduleId;
    String capitalize(String s) =>
        s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s;

    final subjectName = capitalize(subjectId);
    final chapter = extractChapterFromId(moduleId);

    final supervisorsSnap = await firestore
        .collection('user_profiles')
        .doc(uid)
        .collection('supervisors')
        .get();

    if (supervisorsSnap.docs.isEmpty) return;

    final moduleRef = firestore
        .collection('user_profiles')
        .doc(uid)
        .collection('modules')
        .doc(moduleId);

    final moduleSnap = await moduleRef.get();
    final wasCompleted =
        moduleSnap.data()?['quiz_status'] == 'completed';

    final actionText = wasCompleted ? 'retook' : 'completed';

    for (final doc in supervisorsSnap.docs) {
      final supervisorId = doc.id;

      await firestore
          .collection('user_profiles')
          .doc(supervisorId)
          .collection('notifications')
          .add({
        'type': 'quiz',
        'studentId': uid,
        'studentName': studentName,
        'subjectId': subjectName,
        'grade': grade, 
        'chapter': chapter, 
        'moduleId': moduleTitle,
        'status': actionText,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final params = GoRouterState.of(context).pathParameters;
    final subjectId = params['subjectId']!;
    final moduleId = params['moduleId']!;
    final profileProvider = ref.watch(providerUserProfile); 
    final uid = profileProvider.uid;

    final questionsAsync = ref.watch(quizProvider(moduleId));

    return questionsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        body: Center(child: Text('Error loading questions: $err')),
      ),
      
      data: (questions) {
        if (questions.isEmpty) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'No quiz questions available.',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
                        await _saveAndShowResult(
                          context,
                          subjectId,
                          moduleId,
                          questions.length,
                          uid,
                        );
                      },
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
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
                              if (_selected == question.correctIndex && _increase) {
                                _score++;
                              }
                              if (_currentIndex < questions.length - 1) {
                                setState(() {
                                  _currentIndex++;
                                  _selected = null;
                                });
                              } else {
                                _increase = false;
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
}
