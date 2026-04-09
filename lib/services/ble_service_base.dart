import 'dart:async';

typedef AntennaData = (double left, double right);

abstract class BleServiceBase {
  Stream<AntennaData> get challengeStream;
  Stream<AntennaData> get antennaStream;
  Stream<void> get ackStream;

  Future<void> connect(dynamic device);
  Future<void> sendReady();
  Future<void> sendUid(String uid);
  Future<void> disconnect();
  void dispose();
}
