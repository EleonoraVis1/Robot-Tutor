// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/providers/provider_subjects.dart';
import 'package:csc322_starter_app/providers/provider_user_profile.dart';
import 'package:csc322_starter_app/screens/general/students/screen_module.dart';
import 'package:csc322_starter_app/widgets/general/subject_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// App imports
import 'package:csc322_starter_app/screens/general/supervisors/screen_chathistory_supervisor.dart';
import '../../../util/message_display/snackbar.dart';

const List<Map<String, dynamic>> _kSubjects = [
  {'title': 'Math', 'icon': Icons.calculate},
  {'title': 'Korean', 'icon': Icons.language},
  {'title': 'Physics', 'icon': Icons.science},
  {'title': 'English', 'icon': Icons.menu_book},
];

//////////////////////////////////////////////////////////////////////////
// Stateful widget
//////////////////////////////////////////////////////////////////////////
class ScreenStudentinfoSupervisor extends ConsumerStatefulWidget {
  
  static const routeName = '/studentinfo_supervisor';
  final String studentUid;

  const ScreenStudentinfoSupervisor({
    super.key,
    required this.studentUid,
  }); 

  @override
  ConsumerState<ScreenStudentinfoSupervisor> createState() =>
      _ScreenStudentinfoSupervisorState();
}

//////////////////////////////////////////////////////////////////////////
// State
//////////////////////////////////////////////////////////////////////////
class _ScreenStudentinfoSupervisorState
    extends ConsumerState<ScreenStudentinfoSupervisor> {
  bool _isInit = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      _init();
      _isInit = false;
    }
  }

  ////////////////////////////////////////////////////////////////
  // Initialize resources
  ////////////////////////////////////////////////////////////////
  Future<void> _init() async {
    // Load data here if needed
  }

  

  ////////////////////////////////////////////////////////////////
  // Navigation
  ////////////////////////////////////////////////////////////////
  void _openChatHistory() {
    context.push(ScreenChathistorySupervisor.routeName);
  }

  void _openModuleInfo() {
    context.push(ScreenModule.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = ref.watch(providerUserProfile);
    final subjectsAsync = ref.watch(subjectsProvider);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Student Info'),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Chat history',
        child: const Icon(Icons.chat),
        onPressed: () {
          context.push(
            '${ScreenChathistorySupervisor.routeName}/${widget.studentUid}',
          );
        },
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subjects',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: subjectsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (subjects) {
                  if (subjects.isEmpty) {
                    return const Center(child: Text('No subjects available'));
                  }

                  return GridView.builder(
                    itemCount: subjects.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                    ),
                    itemBuilder: (_, i) {
                      final subject = subjects[i];
                      return SubjectCard(
                        title: subject.title,
                        icon: subject.icon,
                        routeName: '/subject/${subject.id}',
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      )
    );
  }
}