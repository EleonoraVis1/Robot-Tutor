// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/providers/provider_ble_connection.dart';
import 'package:csc322_starter_app/providers/provider_subjects.dart';
import 'package:csc322_starter_app/providers/provider_user_profile.dart';
import 'package:csc322_starter_app/screens/general/students/screen_bluetooth_pairing.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_home_supervisor.dart';
import 'package:csc322_starter_app/widgets/general/subject_card.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_app_drawer.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_primary_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenHomeStudent extends ConsumerStatefulWidget {
  static const routeName = '/home_student';

  final bool supervisorView;
  final String? studentUid;

  const ScreenHomeStudent({
    super.key,
    required this.supervisorView,
    required this.studentUid
  });

  @override
  ConsumerState<ScreenHomeStudent> createState() => _ScreenHomeStudentState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenHomeStudentState extends ConsumerState<ScreenHomeStudent> {
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

  @override
  Widget build(BuildContext context) {
    final profileProvider = ref.watch(providerUserProfile);

    if (!widget.supervisorView) {
      ref.listen<BleConnectionState>(bleConnectionProvider, (prev, next) {
        if ((prev?.connected ?? false) && !next.connected && mounted) {
          context.go(ScreenBluetoothPairing.routeName);
        }
      });
    }

    return Scaffold(
      appBar: WidgetPrimaryAppBar(title: const Text('Subjects')),
      drawer: WidgetAppDrawer(),
      body: _buildStudentView(profileProvider),
      floatingActionButton: widget.supervisorView
          ? null
          : Row(
              children: [
                const Spacer(),
                FloatingActionButton(
                  tooltip: 'Upload Files',
                  heroTag: 'Upload-file-tag',
                  child: const Icon(Icons.upload_file_outlined),
                  onPressed: () {
                    context.push('/uploadfile');
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildStudentView(ProviderUserProfile profileProvider) {
    final String firstName = profileProvider.dataLoaded
        ? profileProvider.firstName
        : 'there';
    final subjectsAsync = ref.watch(subjectsProvider);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 5),
          if(!(widget.supervisorView))
            Text(
              'Hello, $firstName! 👋\nWhat would you like to learn today?',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 30),
          const Text(
            'Subjects',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
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
                      routeName: widget.supervisorView ? '${ScreenHomeSupervisor.routeName}/student/${widget.studentUid}/subject/${subject.id}' : '/subject/${subject.id}',
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (!(widget.supervisorView))
            Consumer(
              builder: (ctx, ref, _) {
                final ble = ref.watch(bleConnectionProvider);
                return ElevatedButton(
                  onPressed: ble.connected
                      ? () => ref.read(bleConnectionProvider.notifier).disconnect()
                      : () => context.push(ScreenBluetoothPairing.routeName),
                  child: Text(
                    ble.connected ? 'Disconnect' : 'Connect',
                    style: const TextStyle(fontSize: 16),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
