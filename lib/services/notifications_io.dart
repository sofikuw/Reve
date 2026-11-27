import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _plugin.initialize(const InitializationSettings(android: android));
  await _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<void> notify(String title, String body) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reve_transfers',
      'Transfers',
      channelDescription: 'Upload and backup status',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );
  await _plugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    details,
  );
}
