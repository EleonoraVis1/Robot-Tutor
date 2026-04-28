// Flutter imports
import 'dart:async';
import 'dart:typed_data';

// Flutter external package importer
import 'package:csc322_starter_app/util/logging/app_logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _isInit = true;
  final _formKey = GlobalKey<FormState>();
  var _subjectName = "";
  var _gradeLevel = "";
  var _chapter = "";
  var _lesson = "";

  PlatformFile? _selectedPdf;
  bool _isUploading = false;

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

  Future<void> _pickPdf() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );

      final file = result?.files.single;
      if (file == null) {
        return;
      }

      final lowerName = file.name.toLowerCase();
      if (!lowerName.endsWith('.pdf') || file.bytes == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a valid PDF file'),
          ),
        );
        return;
      }

      setState(() {
        _selectedPdf = file;
      });
    } catch (e) {
      AppLogger.error("Error picking PDF: $e");
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the file picker'),
        ),
      );
    }
  }

  Future<void> _uploadInfo(
    String courseName,
    String glevel,
    String chapter,
    String lesson,
    PlatformFile pdfFile,
  ) async {
    final Uint8List? bytes = pdfFile.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to read the selected PDF'),
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final path = 'raw-uploads/${pdfFile.name}';
      final ref = FirebaseStorage.instance.ref().child(path);

      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: 'application/pdf',
          customMetadata: <String, String>{
            'subject_name': courseName.trim(),
            'subject': courseName.trim(),
            'grade_level': glevel.trim(),
            'grade': glevel.trim(),
            'chapter': chapter.trim(),
            'unit': chapter.trim(),
            'lesson': lesson.trim(),
            'source_type': 'worksheet',
            'original_file_name': pdfFile.name,
          },
        ),
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.error(e.toString());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _cancelAdd() async {
    Navigator.of(context).pop();
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final selectedPdf = _selectedPdf;

    return Scaffold(
      appBar: AppBar(title: const Text("File Uploading"), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                          return null;
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
                          return null;
                        },
                        keyboardType: const TextInputType.numberWithOptions(),
                        onSaved: (value) => _gradeLevel = value!,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        maxLength: 2,
                        decoration: const InputDecoration(
                          labelText: 'Chapter',
                          helperText: 'Unit will be set to the same value',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter a chapter number';
                          }
                          final chapter = int.tryParse(value.trim());
                          if (chapter == null || chapter < 0) {
                            return 'Must be a valid chapter number';
                          }
                          return null;
                        },
                        keyboardType: const TextInputType.numberWithOptions(),
                        onSaved: (value) => _chapter = value!,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        maxLength: 20,
                        decoration: const InputDecoration(
                          labelText: 'Lesson',
                          helperText: 'Use a number or label like Practice',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter a lesson number or label';
                          }
                          if (value.trim().length > 20) {
                            return 'Keep lesson under 20 characters';
                          }
                          return null;
                        },
                        onSaved: (value) => _lesson = value!,
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _isUploading ? null : _pickPdf,
                        child: Container(
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[400]!),
                          ),
                          child: selectedPdf == null
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.picture_as_pdf_outlined,
                                      size: 24,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      "Tap to select PDF",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                )
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.picture_as_pdf,
                                        size: 32,
                                        color: Colors.redAccent,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              selectedPdf.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatFileSize(selectedPdf.size),
                                              style: const TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
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
                              onPressed: _isUploading ? null : _cancelAdd,
                              label: const Text("Cancel"),
                              icon: const Icon(Icons.cancel),
                              style: ElevatedButton.styleFrom(
                                fixedSize: const Size(130, 15),
                                textStyle: const TextStyle(fontSize: 18),
                                iconSize: 18,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isUploading
                                  ? null
                                  : () {
                                      if (_formKey.currentState!.validate()) {
                                        _formKey.currentState!.save();

                                        if (_selectedPdf == null) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Please select a PDF first',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        _uploadInfo(
                                          _subjectName,
                                          _gradeLevel,
                                          _chapter,
                                          _lesson,
                                          _selectedPdf!,
                                        );
                                      }
                                    },
                              icon: _isUploading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              label: Text(_isUploading ? "Uploading" : "Upload"),
                              style: ElevatedButton.styleFrom(
                                fixedSize: const Size(130, 15),
                                textStyle: const TextStyle(fontSize: 18),
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
