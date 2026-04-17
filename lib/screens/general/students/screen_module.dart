// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/models/user_profile.dart';
import 'package:csc322_starter_app/providers/provider_ble_connection.dart';
import 'package:csc322_starter_app/providers/provider_module_result.dart';
import 'package:csc322_starter_app/providers/provider_quiz.dart';
import 'package:csc322_starter_app/providers/provider_subjects.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_home_supervisor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenModule extends ConsumerStatefulWidget {
  static const routeName = '/subject/:subjectId/module/:moduleId';

  final String? studentUid;
  final String subjectId;
  final int grade;
  final String moduleId;

  const ScreenModule({super.key, required this.studentUid, required this.grade, required this.subjectId, required this.moduleId});

  @override
  ConsumerState<ScreenModule> createState() => _ScreenModuleState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenModuleState extends ConsumerState<ScreenModule> {
  // The "instance variables" managed in this state
  bool _isInit = true;
  bool _hasNavigatedToQuiz = false;
  int? _selectedIndex;
  int? _lastQuestionIndex;
  bool _isLastQuestionAnswered = false;
  int _reviewIndex = -1;
  bool _completed = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(providerUserProfile);
      if (profile.dataLoaded && profile.userType != UserType.SUPERVISOR) {
        ref.read(bleConnectionProvider.notifier).sendModuleSelect(widget.moduleId);
      }
    });
  }

  @override
  void dispose() {
    final profile = ref.read(providerUserProfile);
    if (profile.userType != UserType.SUPERVISOR) {
      ref.read(bleConnectionProvider.notifier).sendModuleDeselect();
    }
    super.dispose();
  }

  ////////////////////////////////////////////////////////////////
  // Initializes state variables and resources
  ////////////////////////////////////////////////////////////////
  Future<void> _init() async {}

  @override
  Widget build(BuildContext context) {
    final params = GoRouterState.of(context).pathParameters;
    final subjectId = params['subjectId']!;
    final moduleId = params['moduleId']!;
    final modulesAsync = ref.watch(modulesProvider);
    final profileProvider = ref.watch(providerUserProfile);
    final isSupervisor =
        profileProvider.dataLoaded &&
        profileProvider.userType == UserType.SUPERVISOR;
    final questionsAsync = ref.watch(moduleQuestionsProvider(moduleId));
    final exampleNumAsync = ref.watch(exampleQuestionNumProvider((
      studentId: profileProvider.uid,
      moduleId: moduleId,
    )));
    final statusAsync = ref.read(quizStatusProvider((
      studentId: profileProvider.uid,
      moduleId: widget.moduleId,
    )));
              
    statusAsync.whenData((status) {
      if (status.toLowerCase() == 'completed') {
        _completed = true;
        if (_reviewIndex == -1) {
          _reviewIndex = 0;
        }
      } 
    });

    statusAsync.whenData((status) {
      if (status.toLowerCase() == 'completed') {
        _completed = true;
        if (_reviewIndex == -1) {
          _reviewIndex = 0;
        }
      }
    });

    final isReady =
        profileProvider.dataLoaded &&
        profileProvider.userType != UserType.SUPERVISOR;

    if (isReady) {
      ref.listen(
        quizStartProvider((
          studentId: profileProvider.uid,
          moduleId: widget.moduleId,
        )),
        (previous, next) {
          if (next.value == true && !_hasNavigatedToQuiz) {
            final statusAsync = ref.read(
              quizStatusProvider((
                studentId: profileProvider.uid,
                moduleId: widget.moduleId,
              )));
              
            statusAsync.whenData((status) {
              if (status.toLowerCase() != 'completed' && _isLastQuestionAnswered) {
                _hasNavigatedToQuiz = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    context.push(
                      '/subject/${widget.subjectId}/grade/${widget.grade}/module/${widget.moduleId}/quiz',
                    );
                    _reviewIndex = 0;
                  }
                });
              } 
            });
          }
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: modulesAsync.when(
          loading: () => const Text('Loading module...'),
          error: (_, __) => const Text('Module'),
          data: (modules) {
            final module = modules.firstWhere((m) => m.id == moduleId);
            return Text('Module: ${module.title}');
          },
        ),
        centerTitle: true,
      ),
      floatingActionButton: Consumer(
        builder: (ctx, ref, _) {
          final ble = ref.watch(bleConnectionProvider);
          if (ble.connected) return _buildRobotControls(ctx, ble, ref);
          return FloatingActionButton(
            tooltip: 'Robot controls',
            heroTag: 'robot-controls',
            child: const Icon(Icons.chat),
            onPressed: () {
              if (widget.studentUid == null) {
                context.push('/subject/$subjectId/grade/${widget.grade}/module/$moduleId/chat');
              } else {
                context.push(
                  '${ScreenHomeSupervisor.routeName}/student/${widget.studentUid}/subject/$subjectId/grade/${widget.grade}/module/$moduleId/chat',
                );
              }
            },
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isSupervisor) ...[
              ref.watch(quizStatusProvider((
                studentId: widget.studentUid ?? profileProvider.uid,
                moduleId: moduleId,
              ))).when(
                loading: () => const SizedBox(), 
                error: (_, __) => const SizedBox(),
                data: (status) {
                  if (status.toLowerCase() == 'completed') {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.quiz),
                          label: const Text('Retake Quiz'),
                          onPressed: () {
                            context.push('/subject/$subjectId/grade/${widget.grade}/module/$moduleId/quiz');
                            _reviewIndex = 0;
                          },
                        ),              
                      ],
                    );
                  } else {
                    return const SizedBox();
                  }
                },
              ),
            ] else ...[
              const Text(
                'Quiz Result',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              ref
                  .watch(
                    moduleResultProvider((
                      studentUid: widget.studentUid ?? profileProvider.uid,
                      moduleId: moduleId,
                    )),
                  )
                  .when(
                    loading: () => const CircularProgressIndicator(),
                    error: (e, _) => Text('Error: $e'),
                    data: (doc) {
                      if (doc == null) {
                        return const Card(
                          child: ListTile(
                            leading: Icon(Icons.hourglass_empty),
                            title: Text('Not completed'),
                            subtitle: Text(
                              'Student has not taken this quiz yet',
                            ),
                          ),
                        );
                      }

                      final data = doc.data()!;
                      final score = data['score'];
                      final total = data['totalQuestions'];

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.check_circle_outline),
                          title: Text('Score: $score / $total'),
                          subtitle: const Text('Quiz completed'),
                        ),
                      );
                    },
                  ),
            ],
            const SizedBox(height: 24),
            if (!isSupervisor)
              questionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading questions: $e'),
              data: (questions) {
                return exampleNumAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                  data: (qIndex) {
                    if (qIndex < 0) {
                      return const Center(child: Text('Learning In Progress', style: TextStyle(fontSize: 20),),);
                    }
                
                    final currentIndex = _reviewIndex >= 0 
                        ? _reviewIndex 
                        : (qIndex >= questions.length ? questions.length - 1 : qIndex);

                    final question = questions[currentIndex];

                    if (_lastQuestionIndex != currentIndex) {
                      _selectedIndex = null;
                      _lastQuestionIndex = currentIndex;
                    }

                    if (_lastQuestionIndex != currentIndex) {
                      _selectedIndex = null;
                      _lastQuestionIndex = currentIndex;
                    }

                    Color? getButtonColor(int index) {
                      if (_selectedIndex == null) return null;
                      if (index == _selectedIndex) {
                        return index == question.correctIndex
                            ? Colors.green
                            : Colors.red;
                      }
                      if (_selectedIndex != question.correctIndex &&
                          index == question.correctIndex) {
                        return Colors.green.withOpacity(0.5);
                      }

                      return null;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Question ${currentIndex + 1}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        Text(
                          question.question,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 20),

                        ...List.generate(question.options.length, (index) {
                          final isSelected = _selectedIndex == index;
                          final isCorrect = index == question.correctIndex;

                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ElevatedButton(
                              style: ButtonStyle(
                                backgroundColor:
                                    MaterialStateProperty.resolveWith<Color?>(
                                      (states) {
                                        return getButtonColor(index);
                                      },
                                    ),
                              ),
                              onPressed: _selectedIndex != null
                                  ? null
                                  : () {
                                      setState(() {
                                        _selectedIndex = index;
                                        if (_lastQuestionIndex ==
                                            questions.length - 1) {
                                          _isLastQuestionAnswered = true;

                                          final startQuiz = ref
                                              .read(
                                                quizStartProvider((
                                                  studentId:
                                                      profileProvider.uid,
                                                  moduleId: widget.moduleId,
                                                )),
                                              )
                                              .value;

                                          if (startQuiz == true && !_hasNavigatedToQuiz && !_completed) {
                                            _hasNavigatedToQuiz = true;
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              if (mounted) {
                                                context.push(
                                                  '/subject/${widget.subjectId}/grade/${widget.grade}/module/${widget.moduleId}/quiz',
                                                );
                                                _reviewIndex = 0;
                                              }
                                            });
                                          }
                                        }
                                      });
                                    },
                              child: Text(question.options[index]),
                            ),
                          );
                        }),
                        if (_reviewIndex >= 0)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 30),
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  if (_reviewIndex! < questions.length - 1) {
                                    _reviewIndex = _reviewIndex! + 1;
                                  } else {
                                    _reviewIndex = -1;
                                  }
                                });
                              },
                              child: Text(
                                _reviewIndex! < questions.length - 1
                                    ? 'Next'
                                    : 'Finish Review',
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRobotControls(
      BuildContext ctx, BleConnectionState ble, WidgetRef ref) {
    final notifier = ref.read(bleConnectionProvider.notifier);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              tooltip: ble.micMuted ? 'Unmute microphone' : 'Mute microphone',
              icon: Icon(
                ble.micMuted ? Icons.mic_off : Icons.mic,
                color: ble.micMuted ? Theme.of(ctx).colorScheme.error : null,
              ),
              onPressed: () => notifier.setMicMuted(!ble.micMuted),
            ),
            SizedBox(
              width: 120,
              child: Slider(
                value: ble.volume / 100,
                onChangeEnd: (v) => notifier.setVolume((v * 100).round()),
                onChanged: (_) {},
              ),
            ),
            Text(
              '${ble.volume}%',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            const Icon(Icons.volume_up, size: 20),
          ],
        ),
      ),
    );
  }
}
