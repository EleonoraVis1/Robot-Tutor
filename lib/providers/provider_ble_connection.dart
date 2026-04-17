import 'dart:async';

import 'package:csc322_starter_app/providers/provider_bluetooth.dart';
import 'package:csc322_starter_app/services/ble_service.dart';
import 'package:csc322_starter_app/services/ble_service_base.dart';
import 'package:csc322_starter_app/services/web_ble_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

class BleConnectionState {
  final bool connected;
  final String? deviceName;
  final int volume;
  final bool micMuted;

  const BleConnectionState({
    this.connected = false,
    this.deviceName,
    this.volume = 80,
    this.micMuted = false,
  });

  BleConnectionState copyWith({
    bool? connected,
    String? deviceName,
    int? volume,
    bool? micMuted,
  }) {
    return BleConnectionState(
      connected: connected ?? this.connected,
      deviceName: deviceName ?? this.deviceName,
      volume: volume ?? this.volume,
      micMuted: micMuted ?? this.micMuted,
    );
  }
}

class BleConnectionNotifier extends StateNotifier<BleConnectionState> {
  final Ref _ref;
  final BleServiceBase _service;

  BleConnectionNotifier(this._ref)
      : _service = kIsWeb ? WebBleService() : BleService(),
        super(const BleConnectionState());

  Stream<AntennaData> get challengeStream => _service.challengeStream;
  Stream<AntennaData> get antennaStream => _service.antennaStream;
  Stream<void> get ackStream => _service.ackStream;

  Future<void> sendReady() => _service.sendReady();
  Future<void> sendUid(String uid) => _service.sendUid(uid);

  /// Web only: opens the browser device picker. Returns null on mobile.
  Future<dynamic> scanWeb() async {
    if (!kIsWeb) return null;
    return (_service as WebBleService).scan();
  }

  Future<void> connect(dynamic device, String name, String id) async {
    await _service.connect(device);
    await _ref.read(connectedDeviceProvider.notifier).saveDevice(name, id);
    state = state.copyWith(connected: true, deviceName: name);
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    await _ref.read(connectedDeviceProvider.notifier).removeDevice();
    state = state.copyWith(connected: false, deviceName: null);
  }

  Future<void> setVolume(int v) async {
    if (!state.connected) return;
    state = state.copyWith(volume: v.clamp(0, 100));
    await _service.sendCommand('VOLUME:$v');
  }

  Future<void> setMicMuted(bool muted) async {
    if (!state.connected) return;
    state = state.copyWith(micMuted: muted);
    await _service.sendCommand(muted ? 'MUTE' : 'UNMUTE');
  }

  Future<void> sendModuleSelect(String moduleId) async {
    if (!state.connected) return;
    await _service.sendData('MODULE_SELECT:$moduleId');
    await _service.sendCommand('MODULE_END');
  }

  Future<void> sendModuleDeselect() async {
    if (!state.connected) return;
    await _service.sendCommand('MODULE_DESELECT');
  }
}

final bleConnectionProvider =
    StateNotifierProvider<BleConnectionNotifier, BleConnectionState>(
  (ref) => BleConnectionNotifier(ref),
);
