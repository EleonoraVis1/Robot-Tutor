// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/models/invite.dart';
import 'package:csc322_starter_app/providers/provider_supervisors.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_primary_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenStudentSupervisors extends ConsumerStatefulWidget {
  static const routeName = '/student_supervisors';

  @override
  ConsumerState<ScreenStudentSupervisors> createState() => _ScreenStudentSupervisorsState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenStudentSupervisorsState extends ConsumerState<ScreenStudentSupervisors> {
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
    final uid = ref.watch(providerUserProfile).uid;
    final supervisorsAsync = ref.watch(studentSupervisorsProvider(uid));
    return Scaffold(
      appBar: WidgetPrimaryAppBar(title: const Text('Supervisors')),
      body: supervisorsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (supervisors) {
          if (supervisors.isEmpty) {
            return const Center(
              child: Text(
                'No supervisors assigned yet',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: supervisors.length,
            itemBuilder: (context, index) {
              final supervisor = supervisors[index];
              final name = supervisor['fullName'] ?? 'No Name';
              final email = supervisor['email'] ?? 'No Email';
              final knownAs = supervisor['knownAs'] ?? 'N/A';

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black, width: 1.25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundImage: supervisor['photoUrl'] != null
                        ? NetworkImage(supervisor['photoUrl'])
                        : null,
                    child: supervisor['photoUrl'] == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(email),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Known As:',
                        style: TextStyle(
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        knownAs,
                        style: TextStyle(
                          fontSize: 14,
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
