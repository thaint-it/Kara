import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'services/room_service_keeper.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Phải gọi trước runApp để isolate của foreground service nối được về đây.
  FlutterForegroundTask.initCommunicationPort();
  RoomServiceKeeper.configure();

  runApp(const KaraApp());
}
