import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:guard_monitoring_app/app/core/config/api_constant.dart';
import 'package:guard_monitoring_app/app/repository/auth_repository.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService extends GetxService {
  late io.Socket socket;

  void initConnection() {
    String? token = AuthRepository.instance.getToken();

    socket = io.io(
      ApiConstant.socketServerIpPort,
      <String, dynamic>{
        'path': '/socket.io',
        'transports': ['websocket', 'polling'],
        'autoConnect': true,
        'reconnectionDelay': 1000,
        'reconnectionDelayMax': 5000,
        'reconnectionAttempts': 2,
        'timeout': 20000,
        'query': {'token': token ?? ""}
      },
    );

    socket.connect();

    socket.onConnect((_) {
      debugPrint('Connection established');
    });

    socket.onDisconnect((_) {
      debugPrint('Connection Disconnected');
    });

    socket.onConnectError((err) => debugPrint(err.toString()));
    socket.onError((err) => debugPrint(err.toString()));
  }
}
