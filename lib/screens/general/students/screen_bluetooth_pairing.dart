import 'dart:async';
import 'dart:math';

import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/providers/provider_bluetooth.dart';
import 'package:csc322_starter_app/services/ble_service.dart';
import 'package:csc322_starter_app/services/ble_service_base.dart';
import 'package:csc322_starter_app/services/web_ble_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

const _toleranceRadians = 15 * pi / 180; // 15 degrees

class ScreenBluetoothPairing extends ConsumerStatefulWidget {
  const ScreenBluetoothPairing({super.key});

  @override
  ConsumerState<ScreenBluetoothPairing> createState() =>
      _ScreenBluetoothPairingState();
}

class _ScreenBluetoothPairingState
    extends ConsumerState<ScreenBluetoothPairing> {
  late final BleServiceBase _ble;

  // Mobile scan results
  List<ScanResult> _discovered = [];
  StreamSubscription? _scanSub;

  // Pairing state
  String _status = '';
  bool _started = false;
  (double, double)? _challenge;
  (double, double)? _current;
  bool _matched = false;
  bool _paired = false;
  String? _uid;
  String? _connectedDeviceName;
  String? _connectedDeviceId;

  Timer? _matchTimer;
  StreamSubscription? _antennaSub;
  StreamSubscription? _ackSub;

  @override
  void initState() {
    super.initState();
    _ble = kIsWeb ? WebBleService() : BleService();
    if (!kIsWeb) _startMobileScan();
  }

  Future<void> _requestPermissions() async {
    if (await Permission.bluetoothScan.request().isDenied) return;
    if (await Permission.bluetoothConnect.request().isDenied) return;
    if (await Permission.location.request().isDenied) return;
  }

  Future<void> _startMobileScan() async {
    await _requestPermissions();
    await BleService.startScan(timeout: const Duration(seconds: 30));
    _scanSub = BleService.scanResults.listen((results) {
      if (mounted) setState(() => _discovered = results);
    });
  }

  // ── Web: button-triggered device picker ──────────────────────────────────

  Future<void> _runWeb() async {
    _set('Opening device picker...');
    setState(() => _started = true);
    final device = await (_ble as WebBleService).scan();
    if (device == null) {
      _set('No device selected.');
      setState(() => _started = false);
      return;
    }
    _connectedDeviceName = device.name ?? 'Robot';
    _connectedDeviceId = device.id;
    await _connectAndPair(device);
  }

  // ── Mobile: user picks from list ─────────────────────────────────────────

  Future<void> _connectToDevice(ScanResult r) async {
    _connectedDeviceName =
        r.device.platformName.isNotEmpty ? r.device.platformName : 'Robot';
    _connectedDeviceId = r.device.remoteId.str;
    _scanSub?.cancel();
    await BleService.stopScan();
    await _connectAndPair(r.device);
  }

  // ── Shared connection + pairing flow ─────────────────────────────────────

  Future<void> _connectAndPair(dynamic device) async {
    _set('Connecting...');
    setState(() => _started = true);

    try {
      await _ble.connect(device);
    } catch (e) {
      _set('Connection failed. Please try again.');
      setState(() => _started = false);
      return;
    }

    await Future.delayed(const Duration(milliseconds: 500));
    _set('Sending READY...');
    await _ble.sendReady();
    _set('Waiting for challenge...');

    _challenge = await _ble.challengeStream.first;
    _uid = ref.read(providerUserProfile).uid;
    setState(() {});
    _set('Match the antenna positions.');

    _antennaSub = _ble.antennaStream.listen(_onAntenna);

    _ackSub = _ble.ackStream.listen((_) async {
      final notifier = ref.read(connectedDeviceProvider.notifier);
      await notifier.saveDevice(
          _connectedDeviceName ?? 'Robot', _connectedDeviceId ?? '');
      setState(() => _paired = true);
      _set('Connected!');
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _onAntenna((double, double) pos) {
    setState(() => _current = pos);
    _checkMatch();
  }

  void _checkMatch() {
    final challenge = _challenge;
    final current = _current;
    if (challenge == null || current == null || _paired) return;

    final ok = (current.$1 - challenge.$1).abs() <= _toleranceRadians &&
        (current.$2 - challenge.$2).abs() <= _toleranceRadians;

    if (ok && !_matched) {
      setState(() => _matched = true);
      _matchTimer = Timer(const Duration(seconds: 1), _sendUid);
    } else if (!ok && _matched) {
      setState(() => _matched = false);
      _matchTimer?.cancel();
    }
  }

  Future<void> _sendUid() async {
    await _ble.sendUid(_uid ?? 'unknown');
    _set('Verifying...');
  }

  void _set(String s) => setState(() => _status = s);

  @override
  void dispose() {
    _matchTimer?.cancel();
    _antennaSub?.cancel();
    _ackSub?.cancel();
    _scanSub?.cancel();
    _ble.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final challenge = _challenge;
    final current = _current;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Robot'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Status card (shown once the flow has started)
              if (_started) ...[
                _buildStatusCard(theme),
                const SizedBox(height: 24),
              ],

              // Pairing visual + angle readouts
              if (challenge != null && current != null) ...[
                Center(
                  child: Card(
                    color: Colors.grey.shade200,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _buildPairingVisual(
                        current: current,
                        challenge: challenge,
                        tolerance: _toleranceRadians,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Target:   L=${_fmt(challenge.$1)}  R=${_fmt(challenge.$2)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Current: L=${_fmt(current.$1)}  R=${_fmt(current.$2)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ],

              // Hold / Paired feedback
              if (_matched && !_paired)
                Text(
                  'Hold steady...',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: Colors.green),
                ),
              if (_paired)
                Text(
                  '✓ Connected!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),

              // Pre-start UI
              if (!_started) ...[
                if (kIsWeb) ...[
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.smart_toy_outlined,
                              size: 80, color: theme.colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(
                            'Ready to pair with your robot',
                            style: theme.textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Press Connect to open the device picker.',
                            style: theme.textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: _runWeb,
                            icon: const Icon(Icons.bluetooth),
                            label: const Text('Connect'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Mobile: scan results list
                  if (_discovered.isEmpty) ...[
                    const SizedBox(height: 32),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Scanning for robots...',
                        style: theme.textTheme.bodyMedium),
                  ] else ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Available Robots',
                          style: theme.textTheme.titleMedium),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _discovered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _discovered[i];
                          final name = r.device.platformName.isNotEmpty
                              ? r.device.platformName
                              : 'Unknown Device';
                          return ListTile(
                            leading: const Icon(Icons.smart_toy_outlined),
                            title: Text(name),
                            subtitle: Text('${r.rssi} dBm'),
                            trailing: FilledButton.tonal(
                              onPressed: () => _connectToDevice(r),
                              child: const Text('Connect'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    final (icon, color) = _paired
        ? (Icons.check_circle_outline, Colors.green)
        : _matched
            ? (Icons.adjust, Colors.green)
            : (Icons.bluetooth_searching, theme.colorScheme.primary);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_status, style: theme.textTheme.bodyMedium),
            ),
            if (!_paired && !_matched)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline pairing visual helpers
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildPairingVisual({
  required (double, double) current,
  required (double, double) challenge,
  required double tolerance,
}) {
  return SizedBox(
    width: 350,
    height: 350,
    child: Stack(
      children: [
        Positioned(
          left: 90,
          bottom: 240,
          child: _buildAntennaVisual(current.$1, challenge.$1, tolerance),
        ),
        Positioned(
          right: 90,
          bottom: 240,
          child: _buildAntennaVisual(current.$2, challenge.$2, tolerance),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Image.asset(
            'assets/reachy_mini.png',
            width: 300,
            height: 300,
            fit: BoxFit.contain,
          ),
        ),
      ],
    ),
  );
}

Widget _buildAntennaVisual(double angle, double challenge, double tolerance) {
  return SizedBox(
    width: 60,
    height: 100,
    child: Stack(
      children: [
        CustomPaint(
          size: const Size(60, 150),
          painter: _RangePainter(targetAngle: challenge, tolerance: tolerance),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: angle),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, a, child) => Transform.rotate(
              angle: a,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
            child: Container(
              width: 4,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _RangePainter extends CustomPainter {
  final double targetAngle;
  final double tolerance;

  _RangePainter({required this.targetAngle, required this.tolerance});

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height);
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    const radius = 100.0;
    final path = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..arcTo(
        Rect.fromCircle(center: pivot, radius: radius),
        targetAngle - tolerance - pi / 2,
        tolerance * 2,
        false,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.targetAngle != targetAngle || old.tolerance != tolerance;
}

String _fmt(double rad) => '${(rad * 180 / pi).toStringAsFixed(1)}°';
