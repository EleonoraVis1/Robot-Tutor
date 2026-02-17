// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/providers/provider_user_profile.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_primary_app_bar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

// App relative file imports
import '../../../util/message_display/snackbar.dart';

const List<Map<String, String>> _kPlaceholderStudents = [];

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
  @override
  Widget build(BuildContext context) {
    final profileProvider = ref.watch(providerUserProfile);
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _buildSupervisorView(profileProvider)      
    );
  }

  Widget _buildSupervisorView(ProviderUserProfile profileProvider) {
    final String firstName = profileProvider.dataLoaded
        ? profileProvider.firstName
        : 'Supervisor';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Hello, $firstName! 👋',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Here are your students:',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _kPlaceholderStudents.isEmpty
                ? _buildEmptyStudentState()
                : _buildStudentList(),
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

  Widget _buildStudentList() {
    return ListView.separated(
      itemCount: _kPlaceholderStudents.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final student = _kPlaceholderStudents[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blueGrey[100],
            child: Text(
              student['name']![0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(student['name'] ?? ''),
          subtitle: Text(student['email'] ?? ''),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // TODO: navigate to student detail screen
          },
        );
      },
    );
  }
}
