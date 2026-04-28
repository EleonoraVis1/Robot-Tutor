//////////////////////////////////////////////////////////////////////////
// Imports
//////////////////////////////////////////////////////////////////////////
// Flutter external package imports
import 'package:csc322_starter_app/models/user_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_primary_app_bar.dart';

// App relative file imports
import '../../providers/provider_user_profile.dart';
import '../../util/message_display/snackbar.dart';
import '../../main.dart';

//////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the
// state object.
//////////////////////////////////////////////////////////////////
class ScreenSettings extends ConsumerStatefulWidget {
  const ScreenSettings({super.key});

  static const routeName = '/settings';

  @override
  ConsumerState<ScreenSettings> createState() => _ScreenSettingsState();
}

//////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////
class _ScreenSettingsState extends ConsumerState<ScreenSettings> {
  // The "instance variables" managed in this state
  var _isInit = true;
  late ProviderUserProfile _providerUserProfile;
  late UserType _userType;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_isInit) {
      _providerUserProfile = ref.watch(providerUserProfile);
      _userType = _providerUserProfile.userType;
      _init();
      _isInit = false;
    }
  }

  Future<void> _init() async {
    // Get providers
    _providerUserProfile = ref.watch(providerUserProfile);

    //Get and set the saved pitch and speed
    getCurrentData();
  }

  ////////////////////////////////////////////////////////////////
  // Gets the current data for consumption on
  // this page
  ////////////////////////////////////////////////////////////////
  void getCurrentData() async {}

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  ////////////////////////////////////////////////////////////////
  // Submits the current data to the _providerprofile
  ////////////////////////////////////////////////////////////////
  void _trySubmit() {
    // Unfocus from any controls that may have focus to disengage the keyboard
    FocusScope.of(context).unfocus();

    //Save the data to the provider
    _providerUserProfile.userType = _userType;

    Snackbar.show(SnackbarDisplayType.SB_SUCCESS, 'Save Sucessful', context);
    context.pop();
  }

  // void _setRole() {
  //   if (_userType == UserType.STUDENT) {
  //     _userType = UserType.SUPERVISOR;
  //   } else {
  //     _userType = UserType.STUDENT;
  //   }
  // }

  //////////////////////////////////////////////////////////////////////////
  // Primary Flutter method overriden which describes the layout
  // and bindings for this widget.
  //////////////////////////////////////////////////////////////////////////
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_userType == UserType.STUDENT)
              ElevatedButton(
                onPressed: null, // _setRole,
                child: Text(
                  'Swap to Supervisor (DEMO ONLY)',
                  style: TextStyle(
                    fontSize: 14
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  fixedSize: Size(275, 15)
                ),
              ),
            if (_userType == UserType.SUPERVISOR)
              ElevatedButton(
                onPressed: null, // _setRole,
                child: Text(
                  'Swap to Student (DEMO ONLY)',
                  style: TextStyle(
                    fontSize: 14
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  fixedSize: Size(275, 15)
                ),
              ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: _trySubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  fixedSize: Size(80, 15)
                ), 
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 14
                  ),
                )
              ),
            ),
          ],
        ),
      ),
    );
  }
}
