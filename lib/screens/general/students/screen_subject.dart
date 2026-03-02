// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/providers/provider_subjects.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// App relative file imports
import '../../../util/message_display/snackbar.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenSubject extends ConsumerStatefulWidget {
  static const routeName = '/subject/:subjectId';

  final String subjectId;

  const ScreenSubject({
    super.key,
    required this.subjectId,
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

  
  
  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(subjectsProvider);

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
          ),
          body: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: subject.modules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final module = subject.modules[i];

              return Card(
                elevation: 3,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    context.push(
                      '/subject/${widget.subjectId}/module/${module.id}',
                    );
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
