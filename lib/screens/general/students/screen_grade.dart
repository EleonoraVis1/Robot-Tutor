// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/models/module.dart';
import 'package:csc322_starter_app/models/user_profile.dart';
import 'package:csc322_starter_app/providers/provider_subjects.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_home_supervisor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenGrade extends ConsumerStatefulWidget {
  // static const routeName = '/student/:studentUid/subject/:subjectId';

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
      data['quiz_status'] = 'inaccessible';
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

  @override
  Widget build(BuildContext context) {
    final profileProvider = ref.watch(providerUserProfile);
    final isSupervisor =
        profileProvider.dataLoaded &&
        profileProvider.userType == UserType.SUPERVISOR;

    final studentId = isSupervisor ? widget.studentUid : profileProvider.uid;

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
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (modules) {
        final Map<int, List<Module>> groupedByChapter = {};

        for (final module in modules) {
          final chapter = extractChapter(module.id);

          groupedByChapter.putIfAbsent(chapter, () => []);
          groupedByChapter[chapter]!.add(module);
        }

        final sortedChapters = groupedByChapter.keys.toList()..sort();

        Widget buildModuleCard(Module module, String status) {
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
              side: BorderSide(width: 2, color: Colors.black),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
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
                          color: Colors.blueGrey[600],
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
                          'Grade ' + module.grade_level.toString(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
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

        return Scaffold(
          appBar: AppBar(
            title: Text('Grade ${widget.gradeId}'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: sortedChapters.map((chapter) {
              final chapterModules = groupedByChapter[chapter]!;

              chapterModules.sort((a, b) {
                final aPractice = isPracticeModule(a.id);
                final bPractice = isPracticeModule(b.id);

                if (aPractice && !bPractice) return 1;
                if (!aPractice && bPractice) return -1;

                return extractLesson(a.id).compareTo(extractLesson(b.id));
              });

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
                  children: chapterModules.map((module) {
                    String status = 'not_started';

                    if (studentId != null) {
                      final studentModulesAsync = ref.watch(studentModulesProvider(studentId));

                      return studentModulesAsync.when(
                        loading: () => const SizedBox(),
                        error: (_, __) => const SizedBox(),
                        data: (studentModules) {
                          final moduleData = studentModules[module.id];

                          if (moduleData != null) {
                            final quizStatus = moduleData['quiz_status'] ?? '';
                            status = quizStatus == 'completed'
                                ? 'completed'
                                : 'started';
                          }

                          return buildModuleCard(module, status); // 👈 SAME UI
                        },
                      );
                    }

                    return buildModuleCard(module, status);
                  }).toList(),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
