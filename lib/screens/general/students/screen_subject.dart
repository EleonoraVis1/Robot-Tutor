// Flutter imports
import 'dart:async';

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
    required this.studentUid
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

  Future<void> startModule(String studentId, String moduleId) async {
    final moduleRef = FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(studentId)
        .collection('modules')
        .doc(moduleId);
   

    final messagesRef = moduleRef.collection('messages');

    // Create or update module progress and metadata
    await moduleRef.set({
      'startedAt': FieldValue.serverTimestamp(),
      'completed': false,
      'lastAccessed': FieldValue.serverTimestamp(),
      'messageCount': FieldValue.increment(1), // Optional: track messages
    }, SetOptions(merge: true));

    // Add first system message if this is the first run
    final messagesSnapshot = await messagesRef.limit(1).get();

    if (messagesSnapshot.docs.isEmpty) {
      await messagesRef.add({
        'from': 'system',
        'message': 'Module $moduleId started for $studentId',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> exitModule(String studentId) async {
    final activeModuleRef = FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(studentId);

    await activeModuleRef.set({
      'active_module_id' : ''
    }, SetOptions(merge: true));
  }
  
  @override
  Widget build(BuildContext context) {
    
    final subjectsAsync = ref.watch(subjectsProvider);
    final profileProvider = ref.watch(providerUserProfile);

    final isSupervisor = profileProvider.dataLoaded && profileProvider.userType == UserType.SUPERVISOR;

    return subjectsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
      data: (subjects) {
        final subject = subjects.firstWhere(
          (s) => s.id == widget.subjectId,
          orElse: () => throw Exception('Subject not found'),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(subject.title),
            centerTitle: true,
          ),
          body: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: subject.modules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final module = subject.modules[i];

              return Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    try {
                      if (profileProvider.dataLoaded && !isSupervisor) {
                        await startModule(profileProvider.uid, module.id);
                        await context.push('/subject/${widget.subjectId}/module/${module.id}');
                        await exitModule(profileProvider.uid);

                      } else if (profileProvider.dataLoaded && isSupervisor) {
                        context.push(
                          '${ScreenHomeSupervisor.routeName}/student/${widget.studentUid}/subject/${widget.subjectId}/module/${module.id}',
                        );
                      }

                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to start module'),
                      ),
                    );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
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
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.black38,
                        ),
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
