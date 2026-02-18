// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// App imports
import 'package:csc322_starter_app/screens/general/supervisors/screen_chathistory_supervisor.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_module_supervisor.dart';
import '../../../util/message_display/snackbar.dart';

//////////////////////////////////////////////////////////////////////////
// Stateful widget
//////////////////////////////////////////////////////////////////////////
class ScreenStudentinfoSupervisor extends ConsumerStatefulWidget {
  static const routeName = '/studentinfo_supervisor';

  const ScreenStudentinfoSupervisor({super.key});

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
    context.push(ScreenModuleSupervisor.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Student Info"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _openChatHistory,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text("Chat History"),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 5,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text("Test ${index + 1}"),
                    onTap: _openModuleInfo,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}