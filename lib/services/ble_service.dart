import 'dart:async';
import 'dart:typed_data';
import 'package:csc322_starter_app/services/ble_service_base.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const _serviceUuid       = '2906ab5c-18f2-4a89-b4a9-05a1e7f57ec5';
const _mainCharUuid      = 'df1b5230-7bcb-4930-8d9f-ca7865dae4c7';
const _challengeCharUuid = '7e57417e-84bd-4fc8-9568-08e44d81e839';
const _antennaCharUuid   = '37f02fcb-5045-42d9-96b8-3f893402f607';

class BleService extends BleServiceBase {
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _mainChar;
  BluetoothCharacteristic? _challengeChar;
  BluetoothCharacteristic? _antennaChar;

  final _challengeController   = StreamController<AntennaData>.broadcast();
  final _antennaController     = StreamController<AntennaData>.broadcast();
  final _ackController         = StreamController<void>.broadcast();
  final _disconnectController  = StreamController<void>.broadcast();

  bool _intentionalDisconnect = false;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;

  @override Stream<AntennaData> get challengeStream   => _challengeController.stream;
  @override Stream<AntennaData> get antennaStream     => _antennaController.stream;
  @override Stream<void>        get ackStream         => _ackController.stream;
  @override Stream<void>        get disconnectStream  => _disconnectController.stream;

  /// Starts a scan filtered to the pairing service UUID.
  /// Returns the [Stream] of scan results for the caller to display.
  /// Call [stopScan] when done.
  static Future<void> startScan({Duration timeout = const Duration(seconds: 30)}) {
    return FlutterBluePlus.startScan(
      withServices: [Guid(_serviceUuid)],
      timeout: timeout,
    );
  }

  static Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  static bool get isScanning => FlutterBluePlus.isScanningNow;

  static Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<void> connect(dynamic device) async {
    _intentionalDisconnect = false;
    _connectionStateSub?.cancel();
    _device = device as BluetoothDevice;
    await _device!.connect(license: License.free);

    final services = await _device!.discoverServices();
    final service  = services.firstWhere(
      (s) => s.uuid.toString().toLowerCase() == _serviceUuid.toLowerCase(),
    );

    for (final c in service.characteristics) {
      switch (c.uuid.toString().toLowerCase()) {
        case _mainCharUuid:      _mainChar      = c;
        case _challengeCharUuid: _challengeChar = c;
        case _antennaCharUuid:   _antennaChar   = c;
      }
    }

    await _challengeChar!.setNotifyValue(true, timeout: 30);
    await _antennaChar!.setNotifyValue(true, timeout: 30);
    await _mainChar!.setNotifyValue(true, timeout: 30);

    _challengeChar!.onValueReceived.listen((b) => _challengeController.add(_unpack(b)));
    _antennaChar!.onValueReceived.listen((b)   => _antennaController.add(_unpack(b)));
    _mainChar!.onValueReceived.listen((b) {
      final text = String.fromCharCodes(b).trim();
      if (text == 'ACK') _ackController.add(null);
    });

    _connectionStateSub = _device!.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_intentionalDisconnect) {
        _disconnectController.add(null);
      }
    });
  }

  @override
  Future<void> sendReady() async {
    await _mainChar!.write('READY'.codeUnits, withoutResponse: false);
  }

  @override
  Future<void> sendUid(String uid) async {
    await _mainChar!.write(uid.codeUnits, withoutResponse: false);
  }

  @override
  Future<void> sendCommand(String cmd) async {
    await _mainChar!.write(cmd.codeUnits, withoutResponse: false);
  }

  @override
  Future<void> sendData(String text) async {
    const chunkSize = 20;
    final bytes = text.codeUnits;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final chunk = bytes.sublist(i, (i + chunkSize).clamp(0, bytes.length));
      await _mainChar!.write(chunk, withoutResponse: false);
      if (i + chunkSize < bytes.length) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _connectionStateSub?.cancel();
    _connectionStateSub = null;
    await _device?.disconnect();
  }

  @override
  void dispose() {
    _connectionStateSub?.cancel();
    _challengeController.close();
    _antennaController.close();
    _ackController.close();
    _disconnectController.close();
  }

  AntennaData _unpack(List<int> bytes) {
    final buffer = Uint8List.fromList(bytes).buffer;
    final data   = ByteData.view(buffer);
    return (data.getFloat32(0, Endian.little), data.getFloat32(4, Endian.little));
  }
}
