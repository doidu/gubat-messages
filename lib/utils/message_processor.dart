import 'dart:convert';
import 'dart:isolate';
import 'package:another_telephony/telephony.dart' as telephony_pkg;
import 'package:cryptography_plus/cryptography_plus.dart' as crypto;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/sms_message.dart';
import '../models/queued_message.dart';
import '../models/isolate_models.dart';
import '../services/contact_service.dart';
import '../services/notification_service.dart';

class MessageProcessorIsolate {
  // for batch
  static void _processMessagesInIsolate(LoadMessagesRequest request) async {
    final sendPort = request.sendPort;

    final List<Map<String, dynamic>> processedMessages = [];
    final List<Map<String, dynamic>> queuedMessages = [];

    // Filter new messages
    final newMessages = request.messages.where((msg) {
      final id = msg['id'] as int;
      return !request.existingMessageIds.contains(id);
    }).toList();

    if (newMessages.isEmpty) {
      sendPort.send(LoadMessagesResponse([], []));
      return;
    }

    // Prepare data for batch processing
    final addresses = newMessages.map((m) => m['address'] as String).toList();
    final bodies = newMessages.map((m) => m['body'] as String).toList();

    // Check blocked numbers
    final blockedStatuses = addresses.map((addr) => request.blockedNumbers.contains(addr)).toList();

    // Check spam from address history
    final addressSpamStatuses = addresses.map((addr) => request.spamAddresses.contains(addr)).toList();

    // Check if from contacts
    final contactStatuses = addresses.map((addr) => request.contactAddresses.contains(addr)).toList();

    // Batch spam detection
    List<bool> spamStatuses;
    bool apiFailed = false;
    try {
      // Inline spam detection
      final encryptedMessages = await Future.wait(
        bodies.map((msg) => _encryptMessageIsolate(msg, request.encryptionKey))
      );

      final response = await http.post(
        Uri.parse('${request.apiUrl}/predict'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${request.apiKey}',
        },
        body: jsonEncode({
          'messages': encryptedMessages,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final predictions = data['predictions'] as List<dynamic>?;

        if (predictions != null) {
          spamStatuses = predictions.map((pred) {
            final predictionStr = pred.toString();
            final prediction = int.tryParse(predictionStr) ?? 0;
            return prediction == 1;
          }).toList();
        } else {
          spamStatuses = List.filled(bodies.length, false);
        }
      } else {
        spamStatuses = List.filled(bodies.length, false);
      }
    } catch (e) {
      apiFailed = true;
      spamStatuses = List.filled(bodies.length, false);
      // Create queued messages
      for (var i = 0; i < newMessages.length; i++) {
        final msg = newMessages[i];
        queuedMessages.add({
          'address': msg['address'],
          'body': msg['body'],
          'date': msg['date'],
          'id': msg['id'],
          'queuedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }

    // Process messages
    for (var i = 0; i < newMessages.length; i++) {
      final message = newMessages[i];
      final isBlocked = blockedStatuses[i];
      final hasSpamFromAddr = addressSpamStatuses[i];
      final isSpam = spamStatuses[i];
      final isFromContacts = contactStatuses[i];

      final isSpamDetected = isBlocked || (!isFromContacts && (hasSpamFromAddr || isSpam));

      processedMessages.add({
        'address': message['address'],
        'body': message['body'],
        'date': message['date'],
        'id': message['id'],
        'isSpam': isSpamDetected,
      });
    }

    sendPort.send(LoadMessagesResponse(processedMessages, queuedMessages, apiFailedDueToOffline: apiFailed));
  }
  // for batch
  static Future<String> _encryptMessageIsolate(String message, String encryptionKey) async {
    final algorithm = crypto.AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKeyFromBytes(utf8.encode(encryptionKey).sublist(0, 32));
    final nonce = algorithm.newNonce();

    final secretBox = await algorithm.encrypt(
      utf8.encode(message),
      secretKey: secretKey,
      nonce: nonce,
    );

    final combined = nonce + secretBox.cipherText + secretBox.mac.bytes;
    return base64Encode(combined);
  }

  static Future<bool> _checkSpam(String message, String apiUrl, String apiKey, String encryptionKey) async {
    try {
      final algorithm = crypto.AesGcm.with256bits();
      final secretKey = await algorithm.newSecretKeyFromBytes(utf8.encode(encryptionKey).sublist(0, 32));
      final nonce = algorithm.newNonce();

      final secretBox = await algorithm.encrypt(
        utf8.encode(message),
        secretKey: secretKey,
        nonce: nonce,
      );

      final combined = nonce + secretBox.cipherText + secretBox.mac.bytes;
      final encryptedMessage = base64Encode(combined);

      final response = await http.post(
        Uri.parse('$apiUrl/predict'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'messages': [encryptedMessage],
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final predictions = data['predictions'] as List<dynamic>?;

        if (predictions != null && predictions.isNotEmpty) {
          final predictionStr = predictions[0].toString();
          final prediction = int.tryParse(predictionStr) ?? 0;
          return prediction == 1;
        } else {
          return false;
        }
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
  // for batch
  static Future<LoadMessagesResponse> loadExistingMessagesIsolate(
    List<telephony_pkg.SmsMessage> messages,
    Future<bool> Function(String) hasSpamFromAddress,
    String spamApiUrl,
    String spamApiKey,
    String spamEncryptionKey,
  ) async {
    // Collect data from Hive on main isolate
    final inboxBox = Hive.box<SmsMessage>('inbox');
    final spamBox = Hive.box<SmsMessage>('spam');
    final blockedBox = Hive.box<String>('blocked_numbers');

    // Get existing message IDs
    final Set<int> existingMessageIds = {};
    existingMessageIds.addAll(inboxBox.values.map((m) => m.id));
    existingMessageIds.addAll(spamBox.values.map((m) => m.id));

    // Get blocked numbers
    final Set<String> blockedNumbers = blockedBox.values.toSet();

    // Get spam addresses
    final Set<String> spamAddresses = {};
    for (final message in spamBox.values) {
      spamAddresses.add(message.address);
    }

    // Get contact addresses
    final Set<String> contactAddresses = ContactService().getContactAddresses();

    // Convert messages to serializable format
    final List<Map<String, dynamic>> serializableMessages = messages.map((msg) => {
      'address': msg.address!,
      'body': msg.body!,
      'date': msg.date!,
      'id': msg.id!,
    }).toList();

    // Spawn isolate and get result
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _processMessagesInIsolate,
      LoadMessagesRequest(
        serializableMessages,
        existingMessageIds,
        blockedNumbers,
        spamAddresses,
        contactAddresses,
        receivePort.sendPort,
        spamApiUrl,
        spamApiKey,
        spamEncryptionKey,
      ),
    );

    final response = await receivePort.first as LoadMessagesResponse;

    final Set<String> addressesToMarkAsSpam = {};
    for (final msgData in response.processedMessages) {
      final smsMessage = SmsMessage(
        address: msgData['address'],
        body: msgData['body'],
        date: msgData['date'],
        id: msgData['id'],
        isSpam: msgData['isSpam'],
      );

      if (msgData['isSpam']) {
        await spamBox.add(smsMessage);
        addressesToMarkAsSpam.add(msgData['address']);
      } else {
        await inboxBox.add(smsMessage);
      }
    }

    for (final address in addressesToMarkAsSpam) {
      await markConversationAsSpam(address);
    }

    if (response.queuedMessages.isNotEmpty) {
      final queuedBox = Hive.box<QueuedMessage>('queued_messages');
      for (final queuedData in response.queuedMessages) {
        final queuedMessage = QueuedMessage(
          address: queuedData['address'],
          body: queuedData['body'],
          date: queuedData['date'],
          id: queuedData['id'],
          queuedAt: queuedData['queuedAt'],
        );
        await queuedBox.add(queuedMessage);
      }
    }

    isolate.kill();

    return response;
  }

  static Future<ProcessIncomingResult> processIncomingMessage(
    telephony_pkg.SmsMessage message,
    Future<bool> Function(String) hasSpamFromAddress,
    String spamApiUrl,
    String spamApiKey,
    String spamEncryptionKey,
  ) async {
    try {
      final blockedBox = Hive.box<String>('blocked_numbers');

      // Check if number is blocked
      final isBlocked = blockedBox.values.contains(message.address!);

      // Check for spam
      bool isSpam;
      bool apiFailed = false;
      try {
        isSpam = await _checkSpam(message.body!, spamApiUrl, spamApiKey, spamEncryptionKey);
      } catch (e) {
        apiFailed = true;
        isSpam = false;
        // Queue the message for retry later
        final queuedBox = Hive.box<QueuedMessage>('queued_messages');
        final queuedMessage = QueuedMessage(
          address: message.address!,
          body: message.body!,
          date: message.date!,
          id: message.id!,
          queuedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await queuedBox.add(queuedMessage);
      }
      // print("isBlocked-$isBlocked || (hasContact-${!ContactService().hasContact(message.address!)} && (hasSpam-${await hasSpamFromAddress(message.address!)} || isSpam-$isSpam)}");
      bool isSpamDetected = isBlocked || (!ContactService().hasContact(message.address!) && (await hasSpamFromAddress(message.address!) || isSpam));

      final notificationId = message.id ?? DateTime.now().millisecondsSinceEpoch % 100000;

      final smsMessage = SmsMessage(
        address: message.address!,
        body: message.body!,
        date: message.date!,
        id: notificationId,
        isSpam: isSpamDetected,
      );

      // Store in appropriate box and display notif
      if (isSpamDetected) {
        await NotificationService().showSpamNotification(
          id: notificationId,
          title: "Spam Detected",
          body: "A message from ${ContactService().getDisplayName(message.address!)} was automatically marked as spam and moved to Spam Folder"
        );
        final spamBox = Hive.box<SmsMessage>('spam');
        await spamBox.add(smsMessage);
        // Ensure all messages from this address are marked as spam
        await markConversationAsSpam(message.address!);
      } else {
        await NotificationService().showHamNotification(
          id: notificationId,
          title: ContactService().getDisplayName(message.address!),
          body: message.body!
        );

        final inboxBox = Hive.box<SmsMessage>('inbox');
        await inboxBox.add(smsMessage);
      }

      return ProcessIncomingResult(isSpamDetected, apiFailedDueToOffline: apiFailed);
    } catch (e) {
      // Handle any errors during loading
      return ProcessIncomingResult(false, apiFailedDueToOffline: false);
    }
  }

  // static Future<void> loadExistingMessages(
  //   List<telephony_pkg.SmsMessage> messages,
  //   Future<bool> Function(String) hasSpamFromAddress,
  //   Future<List<bool>> Function(List<String>) isSpam,
  // ) async {
  //   final inboxBox = Hive.box<SmsMessage>('inbox');
  //   final spamBox = Hive.box<SmsMessage>('spam');
  //   final blockedBox = Hive.box<String>('blocked_numbers');

  //   // Filter messages that are not already stored
  //   final newMessages = messages.where((message) {
  //     final existingInbox = inboxBox.values.where((m) => m.id == message.id).isNotEmpty;
  //     final existingSpam = spamBox.values.where((m) => m.id == message.id).isNotEmpty;
  //     return !existingInbox && !existingSpam;
  //   }).toList();

  //   if (newMessages.isEmpty) return;

  //   // Prepare data for batch processing
  //   final addresses = newMessages.map((m) => m.address!).toList();
  //   final bodies = newMessages.map((m) => m.body!).toList();

  //   // Check blocked numbers
  //   final normalizedAddresses = addresses.map(PhoneUtils.normalizePhoneNumber).toList();
  //   final blockedStatuses = normalizedAddresses.map((addr) => blockedBox.values.contains(addr)).toList();

  //   // Check spam from address history
  //   final addressSpamStatuses = await Future.wait(
  //     addresses.map(hasSpamFromAddress)
  //   );

  //   // Batch spam detection
  //   List<bool> spamStatuses;
  //   try {
  //     spamStatuses = await isSpam(bodies);
  //   } catch (e) {
  //     spamStatuses = List.filled(bodies.length, false);
  //     // Queue the messages for retry later
  //     final queuedBox = Hive.box<QueuedMessage>('queued_messages');
  //     for (var i = 0; i < newMessages.length; i++) {
  //       final msg = newMessages[i];
  //       final queuedMessage = QueuedMessage(
  //         address: msg.address!,
  //         body: msg.body!,
  //         date: msg.date!,
  //         id: msg.id!,
  //         queuedAt: DateTime.now().millisecondsSinceEpoch,
  //       );
  //       await queuedBox.add(queuedMessage);
  //     }
  //   }

  //   final Set<String> addressesToMarkAsSpam = {};
  //   for (var i = 0; i < newMessages.length; i++) {
  //     final message = newMessages[i];
  //     final isBlocked = blockedStatuses[i];
  //     final hasSpamFromAddr = addressSpamStatuses[i];
  //     final isSpam = spamStatuses[i];

  //     final isSpamDetected = isBlocked || (!ContactService().hasContact(message.address!) && (hasSpamFromAddr || isSpam));

  //     final smsMessage = SmsMessage(
  //       address: message.address!,
  //       body: message.body!,
  //       date: message.date!,
  //       id: message.id!,
  //       isSpam: isSpamDetected,
  //     );

  //     // Store in appropriate box
  //     if (isSpamDetected) {
  //       await spamBox.add(smsMessage);
  //       addressesToMarkAsSpam.add(message.address!);
  //     } else {
  //       await inboxBox.add(smsMessage);
  //     }
  //   }

  //   // Ensure all messages from spam addresses are marked as spam
  //   for (final address in addressesToMarkAsSpam) {
  //     await markConversationAsSpam(address);
  //   }
  // }

  static Future<void> refreshMessages(
    List<telephony_pkg.SmsMessage> messages,
    Future<bool> Function(String) hasSpamFromAddress,
    Future<List<bool>> Function(List<String>) isSpam,
  ) async {
    final inboxBox = Hive.box<SmsMessage>('inbox');
    final spamBox = Hive.box<SmsMessage>('spam');
    final blockedBox = Hive.box<String>('blocked_numbers');

    // Get the latest message date from our stored messages
    final allStoredMessages = [...inboxBox.values, ...spamBox.values];
    final latestStoredDate = allStoredMessages.isNotEmpty
        ? allStoredMessages.map((m) => m.date).reduce((a, b) => a > b ? a : b)
        : 0;

    // Filter messages that need processing
    final messagesToProcess = messages.where((message) {
      // Skip if already exists (check by ID)
      final existingInbox = inboxBox.values.where((m) => m.id == message.id).isNotEmpty;
      final existingSpam = spamBox.values.where((m) => m.id == message.id).isNotEmpty;
      if (existingInbox || existingSpam) return false;

      // Only process messages newer than our latest stored message
      return message.date! > latestStoredDate;
    }).toList();

    if (messagesToProcess.isEmpty) return;

    // Prepare data for batch processing
    final addresses = messagesToProcess.map((m) => m.address!).toList();
    final bodies = messagesToProcess.map((m) => m.body!).toList();

    // Check blocked numbers
    final blockedStatuses = addresses.map((addr) => blockedBox.values.contains(addr)).toList();

    // Check spam from address history
    final addressSpamStatuses = await Future.wait(
      addresses.map(hasSpamFromAddress)
    );

    // Batch spam detection
    List<bool> spamStatuses;
    try {
      spamStatuses = await isSpam(bodies);
    } catch (e) {
      spamStatuses = List.filled(bodies.length, false);
      // Queue the messages for retry later
      final queuedBox = Hive.box<QueuedMessage>('queued_messages');
      for (var i = 0; i < messagesToProcess.length; i++) {
        final msg = messagesToProcess[i];
        final queuedMessage = QueuedMessage(
          address: msg.address!,
          body: msg.body!,
          date: msg.date!,
          id: msg.id!,
          queuedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await queuedBox.add(queuedMessage);
      }
    }

    final Set<String> addressesToMarkAsSpam = {};
    for (var i = 0; i < messagesToProcess.length; i++) {
      final message = messagesToProcess[i];
      final isBlocked = blockedStatuses[i];
      final hasSpamFromAddr = addressSpamStatuses[i];
      final isSpam = spamStatuses[i];

      final isSpamDetected = isBlocked || (!ContactService().hasContact(message.address!) && (hasSpamFromAddr || isSpam));

      final smsMessage = SmsMessage(
        address: message.address!,
        body: message.body!,
        date: message.date!,
        id: message.id!,
        isSpam: isSpamDetected,
      );

      // Store in appropriate box
      if (isSpamDetected) {
        await spamBox.add(smsMessage);
        addressesToMarkAsSpam.add(message.address!);
      } else {
        await inboxBox.add(smsMessage);
      }
    }

    // Ensure all messages from spam addresses are marked as spam
    for (final address in addressesToMarkAsSpam) {
      await markConversationAsSpam(address);
    }
  }

  static Future<void> markConversationAsSpam(String address) async {
    final inboxBox = Hive.box<SmsMessage>('inbox');
    final spamBox = Hive.box<SmsMessage>('spam');

    // Find all messages from this address in inbox
    final messagesToMove = inboxBox.values.where((msg) => msg.address == address).toList();

    for (var message in messagesToMove) {
      // Remove from inbox
      await message.delete();

      // Create new message marked as spam
      final spamMessage = SmsMessage(
        address: message.address,
        body: message.body,
        date: message.date,
        id: message.id,
        isSpam: true,
      );

      // Add to spam box
      await spamBox.add(spamMessage);
    }
  }

  static Future<void> markConversationAsNotSpam(String address) async {
    final inboxBox = Hive.box<SmsMessage>('inbox');
    final spamBox = Hive.box<SmsMessage>('spam');

    // Find all messages from this address in spam
    final messagesToMove = spamBox.values.where((msg) => msg.address == address).toList();

    for (var message in messagesToMove) {
      // Remove from spam
      await message.delete();

      // Create new message marked as not spam
      final inboxMessage = SmsMessage(
        address: message.address,
        body: message.body,
        date: message.date,
        id: message.id,
        isSpam: false,
      );

      // Add to inbox
      await inboxBox.add(inboxMessage);
    }
  }
}
