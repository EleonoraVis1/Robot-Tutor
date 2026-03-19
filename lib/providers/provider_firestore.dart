import 'package:csc322_starter_app/services/firestore_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final providerFirestoreService = Provider<FirestoreService>((ref) {
  return FirestoreService();
});