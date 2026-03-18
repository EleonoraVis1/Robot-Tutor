// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/models/user_profile.dart';
import 'package:csc322_starter_app/providers/provider_module_result.dart';
import 'package:csc322_starter_app/providers/provider_subjects.dart';
import 'package:csc322_starter_app/screens/general/students/screen_chathistory_student.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_home_supervisor.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// App relative file imports
import '../../../util/message_display/snackbar.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenModule extends ConsumerStatefulWidget {
  static const routeName =
      '/subject/:subjectId/module/:moduleId';

  final String? studentUid;
  final String subjectId;
  final String moduleId;

  const ScreenModule({super.key, required this.studentUid, required this.subjectId, required this.moduleId});

  @override
  ConsumerState<ScreenModule> createState() => _ScreenModuleState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenModuleState extends ConsumerState<ScreenModule> {
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profileProvider = ref.read(providerUserProfile);

      if (profileProvider.dataLoaded &&
          profileProvider.userType != UserType.SUPERVISOR) {
        startModule(profileProvider.uid, widget.moduleId);
      }
    });
  }
  

  
  Future<void> startModule(String studentId, String moduleId) async {
    final ref = FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(studentId);

    final doc = await ref.get();

    if (doc.data()?['active_module_id'] != moduleId) {
      await ref.set({
        'active_module_id': moduleId
      }, SetOptions(merge: true));
    }
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

    final isSupervisor = profileProvider.dataLoaded && profileProvider.userType == UserType.SUPERVISOR;

/*    if (!isSupervisor) {
      startModule(profileProvider.uid, moduleId);
    }*/

    return Scaffold(
      appBar: AppBar(
        title: modulesAsync.when(
          loading: () => const Text('Loading module...'),
          error: (_, __) => const Text('Module'),
          data: (modules) {
            final module = modules.firstWhere(
              (m) => m.id == moduleId,
            );
            return Text( 'Module: ${module.title}');
          },
        ),
        centerTitle: true,
      ),
      floatingActionButton:  FloatingActionButton(
        tooltip: 'Chat history',
        child: const Icon(Icons.chat),
        onPressed: () {

          if (widget.studentUid == null) {
            // student
            context.push(
              '/subject/$subjectId/module/$moduleId/chat',
            );
          } else {
            // supervisor
            context.push(
              '${ScreenHomeSupervisor.routeName}/student/${widget.studentUid}/subject/$subjectId/module/$moduleId/chat',
            );
          }

        },
      ),
      
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isSupervisor) ...[
              // Student view: Start Quiz
              ElevatedButton.icon(
                icon: const Icon(Icons.quiz),
                label: const Text('Start Quiz'),
                onPressed: () {
                  context.push(
                    '/subject/$subjectId/module/$moduleId/quiz',
                  );
                },
              ),
            ] else ...[
              const Text(
                'Quiz Result',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              ref.watch(moduleResultProvider((
                studentUid: widget.studentUid ?? profileProvider.uid,
                moduleId: moduleId,)
              )).when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (doc) {
                  if (doc == null) {
                    return const Card(
                      child: ListTile(
                        leading: Icon(Icons.hourglass_empty),
                        title: Text('Not completed'),
                        subtitle: Text('Student has not taken this quiz yet'),
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
          ],
        ),
      ),
    );
  }
}
