// Flutter imports
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// Flutter external package importer
import 'package:csc322_starter_app/util/logging/app_logger.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenUploadfile extends ConsumerStatefulWidget {
  static const routeName = '/uploadfile';

  @override
  ConsumerState<ScreenUploadfile> createState() => _ScreenUploadFileState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenUploadFileState extends ConsumerState<ScreenUploadfile> {
  // The "instance variables" managed in this state
  bool _isInit = true;
  final _formKey = GlobalKey<FormState>();
  var _subjectName = "";
  var _gradeLevel = "";

  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
  Uint8List? _webImage;

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

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pickedImage = image;
          _webImage = bytes;
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> _uploadInfo(
    String courseName,
    String glevel,
    XFile imageFiles,
  ) async {
    try {
      final path = 'raw-uploads/${imageFiles.name}';
      final ref = FirebaseStorage.instance.ref().child(path);

      File fileToUpload = File(imageFiles.path);

      await ref.putFile(fileToUpload);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.error(e.toString());
    }
  }

  Future<void> _cancelAdd() async {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("File Uploading"), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Upload your files",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        maxLength: 254,
                        decoration: const InputDecoration(
                          labelText: 'Subject Name',
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.isEmpty ||
                              value.trim().length < 3 ||
                              value.trim().length > 254) {
                            return 'Must be between 3 and 254 characters';
                          }
                        },
                        onSaved: (value) => _subjectName = value!,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        maxLength: 2,
                        decoration: const InputDecoration(
                          labelText: 'Grade Level',
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.isEmpty ||
                              value.trim().length < 1 ||
                              value.trim().length > 2) {
                            return 'Must be an exact grade level';
                          }
                        },
                        keyboardType: TextInputType.numberWithOptions(),
                        onSaved: (value) => _gradeLevel = value!,
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[400]!),
                          ),
                          child: _pickedImage == null
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.photo,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                    Text(
                                      "Tap to select image",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    _webImage!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                        child: Text("Could not load preview to this image"),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton.icon(
                              onPressed: _cancelAdd,
                              label: const Text("Cancel"),
                              icon: const Icon(Icons.cancel),
                              style: ElevatedButton.styleFrom(
                                fixedSize: Size(130, 15),
                                textStyle: TextStyle(fontSize: 18),
                                iconSize: 18,
                              ),
                            ),
                          ),
                          Spacer(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (_formKey.currentState!.validate()) {
                                  _formKey.currentState!.save();

                                  if (_pickedImage == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please select an image first',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  _uploadInfo(
                                    _subjectName,
                                    _gradeLevel,
                                    _pickedImage!,
                                  );
                                }
                              },
                              icon: const Icon(Icons.send),
                              label: const Text("Upload"),
                              style: ElevatedButton.styleFrom(
                                fixedSize: Size(130, 15),
                                textStyle: TextStyle(fontSize: 18),
                                iconSize: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
