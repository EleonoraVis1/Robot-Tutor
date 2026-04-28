import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csc322_starter_app/providers/provider_user_profile.dart';
import 'package:flutter_riverpod/legacy.dart';

final connectedDeviceProvider =
    StateNotifierProvider<ConnectedDeviceNotifier, String?>(
  (ref) => ConnectedDeviceNotifier(ref),
);

class ConnectedDeviceNotifier extends StateNotifier<String?> {
  final Ref ref;

  ConnectedDeviceNotifier(this.ref) : super(null) {
    _init();
  }

  Future<void> _init() async {
    final profile = ref.read(providerUserProfile);

    final doc = await FirebaseFirestore.instance
        .collection("user_profiles")
        .doc(profile.uid)
        .get();

    if (doc.exists) {
      state = doc.data()?['connected_device'] as String?;
    }
  }

  Future<void> saveDevice(String deviceName, String deviceId) async {
    state = deviceName;

    final profile = ref.read(providerUserProfile);

    await FirebaseFirestore.instance
        .collection("user_profiles")
        .doc(profile.uid)
        .update({
      "connected_device": deviceName,
      "connected_device_id": deviceId,
    });
  }

  Future<void> removeDevice() async {
    state = null;

    final profile = ref.read(providerUserProfile);

    await FirebaseFirestore.instance
        .collection("user_profiles")
        .doc(profile.uid)
        .update({
      "connected_device": null,
      "connected_device_id": null,
    });
  }
}