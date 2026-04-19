// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/models/module.dart';
import 'package:csc322_starter_app/models/user_profile.dart';
import 'package:csc322_starter_app/providers/provider_subjects.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_home_supervisor.dart';
import 'package:csc322_starter_app/widgets/general/shake_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenGrade extends ConsumerStatefulWidget {

  final String subjectId;
  final int gradeId;
  final String? studentUid;

  const ScreenGrade({
    required this.subjectId,
    required this.gradeId,
    required this.studentUid,
    super.key,
  });

  @override
  ConsumerState<ScreenGrade> createState() => _ScreenGradeState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenGradeState extends ConsumerState<ScreenGrade> {
  // The "instance variables" managed in this state
  bool _isInit = true;
  String? _shakingModuleId;

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

  Future<void> startModule(
    String studentId,
    String moduleId,
    String studentName,
  ) async {
    final moduleRef = FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(studentId)
        .collection('modules')
        .doc(moduleId);
    final messagesRef = moduleRef.collection('messages');

    final moduleSnapshot = await moduleRef.get();
    final isFirstStart = !moduleSnapshot.exists;

    Map<String, dynamic> data = {
      'lastAccessed': FieldValue.serverTimestamp(),
      'messageCount': FieldValue.increment(1),
    };

    if (isFirstStart) {
      data['startedAt'] = FieldValue.serverTimestamp();
      data['quiz_status'] = 'started';
      data['example_question_num'] = -1;
    }

    await moduleRef.set(data, SetOptions(merge: true));

    final messagesSnapshot = await messagesRef.limit(1).get();
    if (messagesSnapshot.docs.isEmpty) {
      await messagesRef.add({
        'from': 'system',
        'message': 'Module \'$moduleId\' started for $studentName',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> exitModule(String studentId) async {
    final activeModuleRef = FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(studentId);
    await activeModuleRef.set({
      'active_module_id': '',
    }, SetOptions(merge: true));
  }

  int extractChapter(String id) {
    final match = RegExp(r'ch(\d+)').firstMatch(id);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  int extractLesson(String id) {
    final match = RegExp(r'les(\d+)').firstMatch(id);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  bool isPracticeModule(String id) {
    final match = RegExp(r'les([^_]+)').firstMatch(id);
    if (match == null) return false;
    final lessonPart = match.group(1)!;
    return lessonPart.toLowerCase().startsWith('practice');
  }

  bool isModuleCompleted(Map<String, dynamic> studentModules, String moduleId) {
    final data = studentModules[moduleId];
    return data?['quiz_status'] == 'completed';
  }

  bool isModuleUnlocked({
    required List<Module> chapterModules,
    required Map<String, dynamic> studentModules,
    required Module module,
  }) {    

    final index = chapterModules.indexWhere((m) => m.id == module.id);
    if (index == 0) return true;
    final previousModule = chapterModules[index - 1];

    return isModuleCompleted(studentModules, previousModule.id);
  }

  List<Module> sortModules(List<Module> modules) {
    final sorted = List<Module>.from(modules);

    sorted.sort((a, b) {
      final aPractice = isPracticeModule(a.id);
      final bPractice = isPracticeModule(b.id);

      if (aPractice && !bPractice) return 1;
      if (!aPractice && bPractice) return -1;

      return extractLesson(a.id).compareTo(extractLesson(b.id));
    });

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = ref.watch(providerUserProfile);
    final isSupervisor =
        profileProvider.dataLoaded &&
        profileProvider.userType == UserType.SUPERVISOR;

    final studentId =
        isSupervisor ? widget.studentUid : profileProvider.uid;

    final modulesAsync = studentId != null
        ? ref.watch(
            modulesByGradeProvider((
              subjectId: widget.subjectId,
              gradeId: widget.gradeId,
            )),
          )
        : const AsyncValue.data([]);

    return modulesAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Error: $e'))),

      data: (modules) {
        final studentModulesAsync = studentId != null
            ? ref.watch(studentModulesProvider(studentId))
            : const AsyncValue.data({});

        final Map<int, List<Module>> groupedByChapter = {};

        for (final module in modules) {
          final chapter = extractChapter(module.id);
          groupedByChapter.putIfAbsent(chapter, () => []);
          groupedByChapter[chapter]!.add(module);
        }

        final sortedChapters = groupedByChapter.keys.toList()..sort();

        Widget buildModuleCard(Module module, String status, {bool isLocked = false}) {
          Color? badgeColor;
          String badgeText = '';

          switch (status) {
            case 'not_started':
              badgeColor = Colors.grey;
              badgeText = 'Not Started';
              break;
            case 'started':
              badgeColor = Colors.orange;
              badgeText = 'Started';
              break;
            case 'completed':
              badgeColor = Colors.green;
              badgeText = 'Completed';
              break;
          }

          return Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(width: 2, color: Colors.black),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: isLocked
              ? () {
                  setState(() {
                    _shakingModuleId = module.id;
                  });
                  final message = isSupervisor
                      ? 'This module is locked for this student. They must complete previous modules first.'
                      : 'This module is locked. Complete previous modules first.';
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      setState(() {
                        _shakingModuleId = null;
                      });
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                }
              : () async {
                  try {
                    if (profileProvider.dataLoaded &&
                        !isSupervisor &&
                        studentId != null) {
                      await startModule(
                        studentId,
                        module.id,
                        profileProvider.wholeName,
                      );

                      await context.push(
                        '/subject/${widget.subjectId}/grade/${widget.gradeId}/module/${module.id}',
                      );

                      await exitModule(studentId);
                    } else if (profileProvider.dataLoaded &&
                        isSupervisor &&
                        studentId != null) {
                      context.push(
                        '${ScreenHomeSupervisor.routeName}/student/$studentId/subject/${widget.subjectId}/grade/${widget.gradeId}/module/${module.id}',
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to start module')),
                    );
                  }
                },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.view_module_outlined,
                          color: isLocked ? Colors.grey : Colors.blueGrey[600],
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            module.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Grade ${module.grade_level}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(
                          isLocked ? Icons.lock : Icons.arrow_forward_ios,
                          size: isLocked ? 26 : 16,
                          color: Colors.blueGrey,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (badgeText.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 230),
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          badgeText,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return studentModulesAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, __) =>
              const Scaffold(body: Center(child: Text("Error loading progress"))),

          data: (rawStudentModules) {
            final Map<String, dynamic> studentModules =
                Map<String, dynamic>.from(rawStudentModules);

            return Scaffold(
              appBar: AppBar(
                title: Text('Grade ${widget.gradeId}'),
                centerTitle: true,
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: sortedChapters.map((chapter) {
                  final chapterModules = groupedByChapter[chapter]!;
                  final sortedChapterModules = sortModules(chapterModules);

                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ExpansionTile(
                      title: Text(
                        'Chapter $chapter',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),

                      children: sortedChapterModules.map((module) {
                        final moduleData =
                            studentModules[module.id] as Map<String, dynamic>?;

                        String status = 'not_started';

                        if (moduleData != null) {
                          final quizStatus = moduleData['quiz_status'];

                          if (quizStatus == 'completed') {
                            status = 'completed';
                          } else if (quizStatus == 'started') {
                            status = 'started';
                          }
                        }

                        final unlocked = isModuleUnlocked(
                          chapterModules: sortedChapterModules,
                          studentModules: studentModules,
                          module: module,
                        );

                        return Opacity(
                          opacity: unlocked ? 1.0 : 0.4,
                          child: ShakeWidget(
                            shake: _shakingModuleId == module.id,
                            child: buildModuleCard(
                              module,
                              status,
                              isLocked: !unlocked,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ),
            );
          },
        );
      },
    );
  }
}