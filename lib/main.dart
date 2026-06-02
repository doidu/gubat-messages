import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'screens/permission_screen.dart';
import 'models/sms_message.dart';
import 'models/queued_message.dart';
import 'services/sms_service.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class SnackBarHidingRouteObserver extends RouteObserver<PageRoute> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (navigatorKey.currentState?.overlay != null) {
      ScaffoldMessenger.of(navigatorKey.currentState!.overlay!.context).hideCurrentSnackBar();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (navigatorKey.currentState?.overlay != null) {
      ScaffoldMessenger.of(navigatorKey.currentState!.overlay!.context).hideCurrentSnackBar();
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //
  try {
    await dotenv.load();
  } catch (e) {
    //
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Hive.initFlutter();
  Hive.registerAdapter(SmsMessageAdapter());
  Hive.registerAdapter(QueuedMessageAdapter());

  // Create encryption cipher
  final encryptionCipher = SmsService.createEncryptionCipher();

  // Open boxes with encryption
  await Hive.openBox<SmsMessage>('inbox', encryptionCipher: encryptionCipher);
  await Hive.openBox<SmsMessage>('spam', encryptionCipher: encryptionCipher);
  await Hive.openBox<QueuedMessage>('queued_messages', encryptionCipher: encryptionCipher);
  await Hive.openBox<String>('blocked_numbers', encryptionCipher: encryptionCipher);

  // Initialize notification service
  await NotificationService().initialize();

  runApp(GubatMessagesApp(encryptionCipher: encryptionCipher));
}

class GubatMessagesApp extends StatelessWidget {
  final HiveAesCipher? encryptionCipher;

  const GubatMessagesApp({super.key, required this.encryptionCipher});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gubat Messages',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      navigatorKey: navigatorKey,
      navigatorObservers: [SnackBarHidingRouteObserver()],
      home: PermissionScreen(cipher: encryptionCipher),
      debugShowCheckedModeBanner: false,
    );
  }
}
