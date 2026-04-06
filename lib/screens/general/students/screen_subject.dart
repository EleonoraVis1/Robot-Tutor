// Flutter imports
import 'dart:async';
import 'dart:math';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
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
class ScreenSubject extends ConsumerStatefulWidget {
  static const routeName = '/student/:studentUid/subject/:subjectId';

  final String subjectId;
  final String? studentUid;

  const ScreenSubject({
    super.key,
    required this.subjectId,
    required this.studentUid,
  });

  @override
  ConsumerState<ScreenSubject> createState() => _ScreenSubjectState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenSubjectState extends ConsumerState<ScreenSubject> {
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

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(subjectsProvider);
    final profileProvider = ref.watch(providerUserProfile);
    final isSupervisor =
        profileProvider.dataLoaded &&
        profileProvider.userType == UserType.SUPERVISOR;

    final studentId = isSupervisor ? widget.studentUid : profileProvider.uid;

    final studentModulesAsync = studentId != null
        ? ref.watch(studentModulesProvider(studentId))
        : const AsyncValue.data({});

    return subjectsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (subjects) {
        final subject = subjects.firstWhere(
          (s) => s.id == widget.subjectId,
          orElse: () => throw Exception('Subject not found'),
        );

        final availableGrades = subject.grades.where((g) => g.modules.isNotEmpty).toList();

        return Scaffold(
          appBar: AppBar(title: Text(subject.title), centerTitle: true),
          body: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: availableGrades.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final grade = availableGrades[i];

              return Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    if (studentId != null) {
                      if (isSupervisor) {
                        context.push(
                          '${ScreenHomeSupervisor.routeName}/student/$studentId/subject/${widget.subjectId}/grade/${grade.id}',
                        );
                      } else {
                        context.push('/subject/${widget.subjectId}/grade/${grade.id}');
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Row(
                      children: [
                        const Icon(Icons.grade, color: Colors.blueGrey, size: 28),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            grade.title,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black38),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
