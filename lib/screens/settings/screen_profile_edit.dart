// -----------------------------------------------------------------------
// Filename: widget_app_drawer.dart
// Original Author: Wyatt Bodle
// Creation Date: 6/10/2024
// Copyright: (c) 2024 CSC322
// Description: This file contains the primary scaffold for the app.

//////////////////////////////////////////////////////////////////////////
// Imports
//////////////////////////////////////////////////////////////////////////
// Flutter external package imports
import 'package:csc322_starter_app/screens/settings/screen_settings.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_app_drawer.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_primary_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_primary_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

// App relative file imports
import '../../widgets/general/widget_scrollable_background.dart';
import '../auth/screen_profile_setup.dart';

final providerPrimaryBottomNavTabIndex = StateProvider<int>((ref) => 0);

//////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the
// state object.
//////////////////////////////////////////////////////////////////
class ScreenProfileSettings extends ConsumerStatefulWidget {
  const ScreenProfileSettings({super.key});

  static const routeName = '/profileSettings';

  @override
  ConsumerState<ScreenProfileSettings> createState() => _ScreenProfileSettingsState();
}

//////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////
class _ScreenProfileSettingsState extends ConsumerState<ScreenProfileSettings> {
  //////////////////////////////////////////////////////////////////////////
  // Primary Flutter method overriden which describes the layout
  // and bindings for this widget.
  //////////////////////////////////////////////////////////////////////////

  Widget _getScreenToDisplay(int currentTabIndex) {
    if (currentTabIndex == BottomNavSelection.PROFILE_SCREEN.index)
      return ScrollableBackground(
        child: ScreenProfileSetup(
          isAuth: false,
        ),
        padding: 20
      );
    else if (currentTabIndex == BottomNavSelection.SETTINGS_SCREEN.index)
      return ScreenSettings();
    else
      return ScrollableBackground(
        child: ScreenProfileSetup(
          isAuth: false,
        ),
        padding: 20
      );
  }

  Widget _getAppBarTitle(int currentTabIndex) {
    if (currentTabIndex == BottomNavSelection.PROFILE_SCREEN.index)
      return Text("Edit Profile");
    else if (currentTabIndex == BottomNavSelection.SETTINGS_SCREEN.index)
      return Text("Settings");
    else 
      return Text("Edit Profile");
  }

  @override
  Widget build(BuildContext context) {
    final currentTabIndex = ref.watch(providerPrimaryBottomNavTabIndex) + 1;
    // Return the widget to show
    return Scaffold(
      appBar: WidgetPrimaryAppBar(
        title: _getAppBarTitle(currentTabIndex),
      ),
      body: _getScreenToDisplay(currentTabIndex),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentTabIndex,
        // onTap: (index) {
        //   ref.read(providerPrimaryBottomNavTabIndex.notifier).state = index;
        // },
        onTap: null,
        items: [
          BottomNavigationBarItem(
            label: "Profile",
            activeIcon: Icon(Icons.person_2_outlined),
            icon: Icon(Icons.person_2_outlined)
          ),
          BottomNavigationBarItem(
            label: "Settings",
            activeIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings)
          ),
        ],
      ),
    );
  }
}
