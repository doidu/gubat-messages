import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:another_telephony/telephony.dart' as telephony_pkg;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/sms_message.dart';
import '../models/queued_message.dart';
import 'spam_detection_service.dart';
import 'firebase_service.dart';
import '../utils/message_processor.dart';

@pragma('vm:entry-point')
Future<void> backgroundMessageHandler(telephony_pkg.SmsMessage message) async {
  try {
    try {
      await dotenv.load();
    } catch (e) {
      //
    }
    await SmsService._ensureHiveInitialized();
    final smsService = SmsService();
    await smsService._handleIncomingMessage(message);
  } catch (e) {
    //
  }
}

class SmsService {
  static void Function()? showOfflineSnackbar;

  // Static completer to ensure Hive initialization happens only once
  static Completer<void>? _hiveInitCompleter;

  static HiveAesCipher createEncryptionCipher() {
    String keyString = dotenv.env['HIVE_KEY'] ?? 'wala-kang-key-sa-hive';
    final key = utf8.encode(keyString);
    final encryptionKey = Uint8List(32)..setRange(0, key.length < 32 ? key.length : 32, key);
    return HiveAesCipher(encryptionKey);
  }

  final String _apiUrl = dotenv.env['API_URL'] ?? 'https://subvertebral-roisterously-marcella.ngrok-free.app';
  final String _encryptionKey = dotenv.env['ENCRYPTION_KEY'] ?? 'wala-kang-encryption-key';
  final String _apiKey = dotenv.env['API_KEY'] ?? 'wala-kang-api-key';


  // Static method to ensure Hive is initialized only once
  static Future<void> _ensureHiveInitialized() async {
    if (Hive.isBoxOpen('inbox')) {
      return; // Already initialized
    }

    if (_hiveInitCompleter != null) {
      return _hiveInitCompleter!.future; // Wait for ongoing initialization
    }

    _hiveInitCompleter = Completer<void>();

    try {
      await Hive.initFlutter();
      Hive.registerAdapter(SmsMessageAdapter());
      Hive.registerAdapter(QueuedMessageAdapter());
      final encryptionCipher = createEncryptionCipher();
      await Hive.openBox<SmsMessage>('inbox', encryptionCipher: encryptionCipher);
      await Hive.openBox<SmsMessage>('spam', encryptionCipher: encryptionCipher);
      await Hive.openBox<String>('blocked_numbers', encryptionCipher: encryptionCipher);
      await Hive.openBox<QueuedMessage>('queued_messages', encryptionCipher: encryptionCipher);

      _hiveInitCompleter!.complete();
    } catch (e) {
      _hiveInitCompleter!.completeError(e);
      _hiveInitCompleter = null; // Reset for retry
      rethrow;
    }
  }

  final telephony_pkg.Telephony telephony = telephony_pkg.Telephony.instance;
  final SpamDetectionService _spamDetectionService = SpamDetectionService();

  Future<void> initialize() async {
    // Try to process any queued messages for retry when app starts (hopefully has connection)
    await _spamDetectionService.processQueuedMessages();

    // Load existing messages
    await _loadExistingMessages();

    // Set up SMS listener for incoming messages
    telephony.listenIncomingSms(
      onNewMessage: _handleIncomingMessage,
      onBackgroundMessage: backgroundMessageHandler,
    );
  }

  Future<void> _loadExistingMessages() async {
    try {
      // Get all SMS messages from device
      final messages = await telephony.getInboxSms(
        columns: [telephony_pkg.SmsColumn.ADDRESS, telephony_pkg.SmsColumn.BODY, telephony_pkg.SmsColumn.DATE, telephony_pkg.SmsColumn.ID],
      );

    final response = await MessageProcessorIsolate.loadExistingMessagesIsolate(
      messages,
      _hasSpamFromAddress,
      _apiUrl,
      _apiKey,
      _encryptionKey,
    );

    if (response.apiFailedDueToOffline && SmsService.showOfflineSnackbar != null) {
      SmsService.showOfflineSnackbar!();
    }
    } catch (e) {
      // Handle any errors during loading
    }
  }

  Future<void> _handleIncomingMessage(telephony_pkg.SmsMessage message) async {
    final result = await MessageProcessorIsolate.processIncomingMessage(
      message,
      _hasSpamFromAddress,
      _apiUrl,
      _apiKey,
      _encryptionKey,
    );

    if (result.apiFailedDueToOffline && SmsService.showOfflineSnackbar != null) {
      SmsService.showOfflineSnackbar!();
    }
  }

  Future<void> refreshMessages() async {
    try {
      // Try to process any queued messages for retry when refreshing (if connection is available)
      await _spamDetectionService.processQueuedMessages();

      // Get all SMS messages from device
      final messages = await telephony.getInboxSms(
        columns: [telephony_pkg.SmsColumn.ADDRESS, telephony_pkg.SmsColumn.BODY, telephony_pkg.SmsColumn.DATE, telephony_pkg.SmsColumn.ID],
      );

      await MessageProcessorIsolate.refreshMessages(
        messages,
        _hasSpamFromAddress,
        _spamDetectionService.isSpam,
      );
    } catch (e) {
      //
    }
  }

  Future<bool> _hasSpamFromAddress(String address) async {
    final spamBox = Hive.box<SmsMessage>('spam');
    return spamBox.values.any((message) => message.address == address);
  }

  // Future<void> toggleSpamStatus(SmsMessage message) async {
  //   final currentIsSpam = message.isSpam;

  //   // Remove from current box
  //   await message.delete();

  //   // Create new message with toggled spam status
  //   final updatedMessage = SmsMessage(
  //     address: message.address,
  //     body: message.body,
  //     date: message.date,
  //     id: message.id,
  //     isSpam: !currentIsSpam,
  //   );

  //   // Add to new box
  //   if (currentIsSpam) {
  //     final inboxBox = Hive.box<SmsMessage>('inbox');
  //     await inboxBox.add(updatedMessage);
  //   } else {
  //     final spamBox = Hive.box<SmsMessage>('spam');
  //     await spamBox.add(updatedMessage);
  //   }

  //   // If marking as spam, ensure ALL messages from this address are also marked as spam
  //   if (!currentIsSpam) {
  //     await MessageProcessorIsolate.markConversationAsSpam(message.address);
  //   }
  // }

  Future<bool> reportConversationAsSpam(String address) async {
    final spamBox = Hive.box<SmsMessage>('spam');
    bool reportSuccess = true;

    // Find messages from this address in spam
    final messages = spamBox.values.where((msg) => msg.address == address).toList();

    for (var message in messages) {
      if (!await FirebaseService().reportSpam(message.body)) {
        reportSuccess = false;
        break; // If any message fails to report, add as failed
      }
    }

    return reportSuccess && messages.isNotEmpty; // Also ensure there were messages to report
  }
}
