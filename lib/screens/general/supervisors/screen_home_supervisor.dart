// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/providers/provider_students.dart';
import 'package:csc322_starter_app/providers/provider_user_profile.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_addstudent_supervisor.dart';
import 'package:csc322_starter_app/widgets/general/student_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenHomeSupervisor extends ConsumerStatefulWidget {
  static const routeName = '/home_supervisor';

  @override
  ConsumerState<ScreenHomeSupervisor> createState() => _ScreenHomeSupervisorState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenHomeSupervisorState extends ConsumerState<ScreenHomeSupervisor> {
  // The "instance variables" managed in this state
  bool _isInit = true;

  ////////////////////////////////////////////////////////////////
  // Runs the following code once upon initialization
  ////////////////////////////////////////////////////////////////
  @override
  void didChangeDependencies() {
    // If first time running this code, update provider settings
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

  //////////////////////////////////////////////////////////////////////////
  // Primary Flutter method overridden which describes the layout and bindings for this widget.
  //////////////////////////////////////////////////////////////////////////
  void _openAddStudents() {
    context.push(ScreenAddStudentSupervisor.routeName);
  }

  void _openStudentInfo(String studentId) {
    context.push(
      '${ScreenHomeSupervisor.routeName}/student/${studentId}',
    );
  }

  Future<void> _removeStudent(String studentId) async {
    final supervisorUid = ref.read(providerUserProfile).uid;
    final firestore = FirebaseFirestore.instance;

    try {
      final batch = firestore.batch();

      final supervisorRef = firestore
          .collection('user_profiles')
          .doc(supervisorUid)
          .collection('students')
          .doc(studentId);

      final studentRef = firestore
          .collection('user_profiles')
          .doc(studentId)
          .collection('supervisors')
          .doc(supervisorUid);

      batch.delete(supervisorRef);
      batch.delete(studentRef);

      await batch.commit();
    } catch (e) {
      debugPrint('Error removing student: $e');
    }
  }

  Future<void> _confirmRemoveStudent(String studentId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Student'),
        content: Text('Are you sure you want to remove $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _removeStudent(studentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = ref.watch(providerUserProfile);
    return Scaffold(
      body: _buildSupervisorView(profileProvider), 
    );
  }

  Widget _buildSupervisorView(ProviderUserProfile profileProvider) {
    final String firstName = profileProvider.dataLoaded
        ? profileProvider.firstName
        : 'Supervisor';
    final studentsAsync = ref.watch(studentsProvider);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 5),
          Text(
            'Hello, $firstName! 👋',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Text(
                'Here are your students:',
                style: TextStyle(fontSize: 18),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _openAddStudents,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  fixedSize: Size(150, 15)
                ),
                icon: const Icon(Icons.add),
                label: const Text(
                  "Add Student",
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: studentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (students) {
                if (students.isEmpty) {
                  return _buildEmptyStudentState();  
                }

                return ListView.builder(
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final student = students[index];

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: BoxBorder.all(color: Colors.black, width: 1.25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => _confirmRemoveStudent(student.id, student.fullName),
                              child: const Icon(Icons.close, color: Colors.red),
                            ),
                            const SizedBox(width: 10),
                            StudentAvatar(student: student),
                          ],
                        ),
                        title: Text(
                          student.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(student.email),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey,
                        ),
                        onTap: () {
                          _openStudentInfo(student.id);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStudentState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_outlined, size: 72, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No students yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Students will appear here once assigned.',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
