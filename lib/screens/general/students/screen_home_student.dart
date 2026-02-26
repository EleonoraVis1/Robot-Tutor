// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/providers/provider_user_profile.dart';
import 'package:csc322_starter_app/screens/general/students/screen_module.dart';
import 'package:csc322_starter_app/widgets/general/subject_card.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_primary_app_bar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// App relative file imports
import '../../../util/message_display/snackbar.dart';

const List<Map<String, dynamic>> _kSubjects = [
  {'title': 'Math', 'icon': Icons.calculate},
  {'title': 'Korean', 'icon': Icons.language},
  {'title': 'Physics', 'icon': Icons.science},
  {'title': 'English', 'icon': Icons.menu_book},
];

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenHomeStudent extends ConsumerStatefulWidget {
  static const routeName = '/home_student';

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

    return Scaffold(
      backgroundColor: Colors.grey[100],
      //appBar: WidgetPrimaryAppBar(title: const Text('Welcome')),
      body: _buildStudentView(profileProvider)
    );
  }

  Widget _buildStudentView(ProviderUserProfile profileProvider) {
    final String firstName = profileProvider.dataLoaded
        ? profileProvider.firstName
        : 'there';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Hello, $firstName! 👋\nWhat would you like to learn today?',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          const Text(
            'Subjects',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: _kSubjects.map((s) { 
                  return SubjectCard(
                    title: s['title'] as String,
                    icon: s['icon'] as IconData,
                  );
                }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
