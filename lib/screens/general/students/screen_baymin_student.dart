// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/models/robot_persona.dart';
import 'package:csc322_starter_app/providers/provider_robot_persona.dart';
import 'package:csc322_starter_app/services/robot_persona_service.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_primary_app_bar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

// App relative file imports
import '../../../util/message_display/snackbar.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenBayminStudent extends ConsumerStatefulWidget {
  static const routeName = '/baymin_student';

  @override
  ConsumerState<ScreenBayminStudent> createState() => _ScreenBaymindStudentState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenBaymindStudentState extends ConsumerState<ScreenBayminStudent> {
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
    final personaAsync = ref.watch(robotPersonaProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Choose Your Robot"),
      ),
      body: personaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Error: $e")),
        data: (currentPersona) {
          return Column(
            children: [
              const SizedBox(height: 40),

              Expanded(
                
                  child: GridView.builder(
                    padding: const EdgeInsets.all(20),
                    
                    itemCount: robotPersonas.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, index) {
                      final persona = robotPersonas[index];
                      final selected = persona.id == currentPersona;

                      return _buildPersonaCard(persona, selected);
                    },
                  ),
                
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPersonaCard(RobotPersona persona, bool selected) {
    return GestureDetector(
      onTap: () async {
        await ref.read(robotPersonaServiceProvider).setPersona(persona.id);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: persona.color.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              border: selected
                  ? Border.all(color: Colors.black, width: 3)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  persona.icon,
                  size: 50,
                  color: Colors.white,
                ),
                const SizedBox(height: 10),
                Text(
                  persona.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Check icon overlay (doesn't affect layout)
          if (selected)
            Positioned(
              top: -8,
              right: -8,
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.check,
                  size: 18,
                  color: Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
