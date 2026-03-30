// Flutter imports
import 'dart:async';
import 'dart:convert';

// Flutter external package importer
import 'package:csc322_starter_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:csc322_starter_app/models/user_profile.dart';
import 'package:csc322_starter_app/providers/provider_user_profile.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenTestBluetooth extends ConsumerStatefulWidget {
  //static const routeName = '/test_bluetooth';

  @override
  ConsumerState<ScreenTestBluetooth> createState() => _ScreenTestBluetoothState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenTestBluetoothState extends ConsumerState<ScreenTestBluetooth> {
  // The "instance variables" managed in this state
  bool _isInit = true;
  final FlutterBluePlus flutterBlue = FlutterBluePlus(); 
  final List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _connectedDevice;
  String _connectionState = "Not connected";

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
    startScan();
  }

  ////////////////////////////////////////////////////////////////
  // Initializes state variables and resources
  ////////////////////////////////////////////////////////////////
  Future<void> _init() async {}

  Future<void> requestBluetoothPermissions() async {
    if (await Permission.bluetoothScan.request().isDenied) {
      // Handle denied
      return;
    }

    if (await Permission.bluetoothConnect.request().isDenied) {
      // Handle denied
      return;
    }

    if (await Permission.location.request().isDenied) {
      // Handle denied
      return;
    }
  }

  void startScan() async {
    await requestBluetoothPermissions();
    FlutterBluePlus.startScan(timeout: Duration(seconds: 5));

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (!_devicesList.contains(r.device)) {
          setState(() {
            _devicesList.add(r.device);
          });
        }
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(license: License.free);

      setState(() {
        _connectedDevice = device;
        _connectionState = "Connected to ${device.name}";
      });

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            _connectionState = "Disconnected";
            _connectedDevice = null;
          });
        }
      });

      // Discover services and print characteristics
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        debugPrint("Service: ${service.uuid}");
        for (var c in service.characteristics) {
          debugPrint(
              "  Characteristic: ${c.uuid} (Read:${c.properties.read} Write:${c.properties.write} Notify:${c.properties.notify})");
        }
      }
    } catch (e) {
      debugPrint("Connection error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }

  Future<void> sendTestData(String uid) async {
    if (_connectedDevice == null) return;

    List<BluetoothService> services = await _connectedDevice!.discoverServices();

    for (var service in services) {
      for (var c in service.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          try {
            await c.write(
              utf8.encode(uid),
              withoutResponse: !c.properties.write,
            );
            debugPrint("Sent UID $uid to ${c.uuid}!");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sent UID $uid to ${c.uuid}")),
            );
            return;
          } catch (e) {
            debugPrint("Write failed for ${c.uuid}: $e");
          }
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No writable characteristic found")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bluetooth Test"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: startScan,
          )
        ],
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Connection Status: $_connectionState",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _devicesList.length,
              itemBuilder: (context, index) {
                final device = _devicesList[index];
                return ListTile(
                  title: Text(device.name.isNotEmpty ? device.name : "Unknown Device"),
                  subtitle: Text(device.id.id),
                  trailing: ElevatedButton(
                    onPressed: _connectedDevice == null
                        ? () => _connectToDevice(device)
                        : null,
                    child: const Text("Connect"),
                  ),
                );
              },
            ),
          ),
          if (_connectedDevice != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Consumer(
              builder: (context, ref, _) {
                final profileProvider = ref.watch(providerUserProfile);
                final uid = profileProvider.uid ?? "unknown_uid";

                return ElevatedButton(
                  onPressed: () => sendTestData(uid),
                  child: const Text("Send My UID"),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
