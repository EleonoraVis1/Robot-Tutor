// Flutter imports
import 'dart:async';
import 'dart:convert';

// Flutter external package importer
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/providers/provider_bluetooth.dart';
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
  BluetoothCharacteristic? _notifyCharacteristic;
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
  Future<void> _init() async {
    final profileProvider = ref.read(providerUserProfile);
    final uid = profileProvider.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection("user_profiles")
        .doc(uid)
        .get();

    final savedDeviceId = doc.data()?['connected_device_id'] as String?;
    final savedDeviceName = doc.data()?['connected_device'] as String?;

    if (savedDeviceId != null && savedDeviceName != null) {
      setState(() {
        _connectionState = "Restoring connection to $savedDeviceName...";
      });

      BluetoothDevice? device;
      int attempts = 0;
      while (device == null && attempts < 10) { 
        device = _devicesList.cast<BluetoothDevice?>().firstWhere(
          (d) => d!.id.id == savedDeviceId,
          orElse: () => null,
        );
        if (device == null) {
          await Future.delayed(Duration(seconds: 1));
        }
        attempts++;
      }

      if (device != null) {
        await _connectToDevice(device);
        // Provider state is already correct from Firestore
        setState(() {
        // _connectionState = "Connected to ${savedDeviceName}";
        });
      } else {
        debugPrint("Saved device not found in scan");

        final notifier = ref.read(connectedDeviceProvider.notifier);
        await notifier.removeDevice();

        setState(() {
          _connectionState = "Disconnected";
          _connectedDevice = null;
        });
      }
    }
  }

  Future<void> requestBluetoothPermissions() async {
    if (await Permission.bluetoothScan.request().isDenied) {
      return;
    }

    if (await Permission.bluetoothConnect.request().isDenied) {
      return;
    }

    if (await Permission.location.request().isDenied) {
      return;
    }
  }

  void startScan() async {
    await requestBluetoothPermissions();
    FlutterBluePlus.startScan(timeout: Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final name = r.advertisementData.localName.isNotEmpty
          ? r.advertisementData.localName.toLowerCase()
          : r.device.name.toLowerCase();

        if (name.contains("bay-min")) {
          if (!_devicesList.any((d) => d.id == r.device.id)) {
            setState(() {
              _devicesList.add(r.device);
            });
          }
        }
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final notifier = ref.read(connectedDeviceProvider.notifier);

    try {
      setState(() {
        _connectionState = "Connecting to ${device.name}...";
      });

      await device.connect(license: License.free);
      final profileProvider = ref.watch(providerUserProfile);
      final uid = profileProvider.uid ?? "unknown_uid";

      await notifier.saveDevice(device.name, device.id.id);
      setState(() {
        _connectedDevice = device;
        _connectionState = "Connected to ${device.name}";
        sendTestData(uid);
      });

      device.connectionState.listen((state) async {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint("${device.name} disconnected");
          await notifier.removeDevice();
          setState(() {
            _connectedDevice = null;
            _connectionState = "Disconnected";
          });
        }
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var c in service.characteristics) {
          if (c.properties.notify) {
            _notifyCharacteristic = c;
            await c.setNotifyValue(true);
            c.lastValueStream.listen((value) {
              final message = utf8.decode(value);
              debugPrint("Received: $message");
              if (message == "ACK") {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Robot acknowledged UID!")),
                );
                Navigator.of(context).pop();
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Connection failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e')),
        );

      await notifier.removeDevice();
      setState(() {
        _connectedDevice = null;
        _connectionState = "Failed to connect";
      });
    }
  }

  Future<void> _disconnectDevice() async {
    if (_connectedDevice == null) return;
    final notifier = ref.read(connectedDeviceProvider.notifier);

    try {

      await sendDisconnectMessage();

      await notifier.removeDevice();

      await _connectedDevice?.disconnect();

      setState(() {
        _connectedDevice = null;
        _connectionState = "Disconnected";
      });
    } catch (e) {
      debugPrint("Error during disconnect: $e");
      setState(() {
        _connectedDevice = null;
        _connectionState = "Disconnected (with errors)";
      });
      await notifier.removeDevice();
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
            
          } catch (e) {
            debugPrint("Write failed for ${c.uuid}: $e");
          }
        }
      }
    }
  }

  Future<void> sendDisconnectMessage() async {
    if (_connectedDevice == null) return;

    List<BluetoothService> services = await _connectedDevice!.discoverServices();
    for (var service in services) {
      for (var c in service.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          try {
            await c.write(
              utf8.encode("DISCONNECT"),
              withoutResponse: !c.properties.write,
            );
            debugPrint("Sent DISCONNECT to ${c.uuid}");
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sent DISCONNECT to ${c.uuid}")),
            );
          } catch (e) {
            debugPrint("Failed to send DISCONNECT to ${c.uuid}: $e");
          }
        }
      }
    }
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
                  trailing: Consumer(
                    builder: (context, ref, child) {
                      final connectedDeviceName = ref.watch(connectedDeviceProvider);
                      final isConnectedToThisDevice = connectedDeviceName == device.name;

                      return ElevatedButton(
                        onPressed: () async {
                          final notifier = ref.read(connectedDeviceProvider.notifier);
                          if (isConnectedToThisDevice) {
                            await _disconnectDevice();
                          } else {
                            await _connectToDevice(device);
                          }
                        },
                        child: Text(isConnectedToThisDevice ? "Disconnect" : "Connect"),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
