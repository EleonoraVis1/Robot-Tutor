import 'dart:async';
import 'dart:typed_data';
import 'package:csc322_starter_app/services/ble_service_base.dart';
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';

const _serviceUuid       = '2906ab5c-18f2-4a89-b4a9-05a1e7f57ec5';
const _mainCharUuid      = 'df1b5230-7bcb-4930-8d9f-ca7865dae4c7';
const _challengeCharUuid = '7e57417e-84bd-4fc8-9568-08e44d81e839';
const _antennaCharUuid   = '37f02fcb-5045-42d9-96b8-3f893402f607';

class WebBleService extends BleServiceBase {
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _mainChar;
  BluetoothCharacteristic? _challengeChar;
  BluetoothCharacteristic? _antennaChar;

  final _challengeController = StreamController<AntennaData>.broadcast();
  final _antennaController   = StreamController<AntennaData>.broadcast();
  final _ackController       = StreamController<void>.broadcast();

  @override Stream<AntennaData> get challengeStream => _challengeController.stream;
  @override Stream<AntennaData> get antennaStream   => _antennaController.stream;
  @override Stream<void>        get ackStream       => _ackController.stream;

  /// Shows the browser's native BLE device picker. Returns the selected device
  /// or null if the user cancelled or Web Bluetooth is not supported.
  Future<BluetoothDevice?> scan({Duration timeout = const Duration(seconds: 30)}) async {
    final supported = FlutterWebBluetooth.instance.isBluetoothApiSupported;
    if (!supported) return null;

    try {
      final options = RequestOptionsBuilder(
        [RequestFilterBuilder(services: [_serviceUuid])],
      );
      return await FlutterWebBluetooth.instance.requestDevice(options);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> connect(dynamic device) async {
    _device = device as BluetoothDevice;
    await _device!.connect();

    final services = await _device!.discoverServices();
    final service  = services.firstWhere(
      (s) => s.uuid.toLowerCase() == _serviceUuid.toLowerCase(),
    );

    _mainChar      = await service.getCharacteristic(_mainCharUuid);
    _challengeChar = await service.getCharacteristic(_challengeCharUuid);
    _antennaChar   = await service.getCharacteristic(_antennaCharUuid);

    await _challengeChar!.startNotifications();
    _challengeChar!.value.listen((bytes) => _challengeController.add(_unpack(bytes)));

    await _antennaChar!.startNotifications();
    _antennaChar!.value.listen((bytes) => _antennaController.add(_unpack(bytes)));

    await _mainChar!.startNotifications();
    _mainChar!.value.listen((bytes) {
      final list = Uint8List.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
      final text = String.fromCharCodes(list).trim();
      if (text == 'ACK') _ackController.add(null);
    });
  }

  @override
  Future<void> sendReady() async {
    bool sent = false;
    while (!sent) {
      try {
        await _mainChar!.writeValueWithResponse(Uint8List.fromList('READY'.codeUnits));
        sent = true;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  @override
  Future<void> sendUid(String uid) async {
    const chunkSize = 20;
    final bytes = Uint8List.fromList(uid.codeUnits);
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(i, end);
      bool sent = false;
      while (!sent) {
        try {
          await _mainChar!.writeValueWithResponse(Uint8List.fromList(chunk));
          sent = true;
        } catch (_) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      if (end < bytes.length) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  @override
  Future<void> sendCommand(String cmd) async {
    bool sent = false;
    while (!sent) {
      try {
        await _mainChar!.writeValueWithResponse(Uint8List.fromList(cmd.codeUnits));
        sent = true;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  @override
  Future<void> sendData(String text) async {
    const chunkSize = 20;
    final bytes = Uint8List.fromList(text.codeUnits);
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(i, end);
      bool sent = false;
      while (!sent) {
        try {
          await _mainChar!.writeValueWithResponse(chunk);
          sent = true;
        } catch (_) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      if (end < bytes.length) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _device?.disconnect();
  }

  @override
  void dispose() {
    _challengeController.close();
    _antennaController.close();
    _ackController.close();
  }

  AntennaData _unpack(ByteData bytes) {
    return (
      bytes.getFloat32(0, Endian.little),
      bytes.getFloat32(4, Endian.little),
    );
  }
}
