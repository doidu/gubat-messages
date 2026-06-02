import 'dart:convert';
import 'dart:isolate';
import 'package:http/http.dart' as http;
import 'package:cryptography_plus/cryptography_plus.dart' as crypto;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/queued_message.dart';
import '../models/sms_message.dart';
import '../models/isolate_models.dart';
import '../utils/message_processor.dart';

class SpamDetectionService {
  static void Function()? showOfflineSnackbar;

  static String get _apiUrl => dotenv.env['API_URL'] ?? 'https://subvertebral-roisterously-marcella.ngrok-free.app';
  static String get _encryptionKey => dotenv.env['ENCRYPTION_KEY'] ?? 'wala-kang-encryption-key';
  static String get _apiKey => dotenv.env['API_KEY'] ?? 'wala-kang-api-key';

  Future<String> _encryptMessage(String message) async {
    final algorithm = crypto.AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKeyFromBytes(utf8.encode(_encryptionKey).sublist(0, 32)); // 256-bit key
    final nonce = algorithm.newNonce(); // 12 bytes for GCM

    final secretBox = await algorithm.encrypt(
      utf8.encode(message),
      secretKey: secretKey,
      nonce: nonce,
    );

    // Concatenate nonce + ciphertext + mac for compatibility
    final combined = nonce + secretBox.cipherText + secretBox.mac.bytes;
    return base64Encode(combined);
  }

  Future<bool> checkApiKey() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/health'), // Assuming you have a health endpoint
        headers: {
          'Authorization': 'Bearer $_apiKey',
        },
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<bool>> isSpam(List<String> messages) async {
    try {
      final encryptedMessages = await Future.wait(
        messages.map((msg) => _encryptMessage(msg))
      );

      final response = await http.post(
        Uri.parse('$_apiUrl/predict'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'messages': encryptedMessages,
        }),
      ).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final predictions = data['predictions'] as List<dynamic>?;

        if (predictions != null) {
          return predictions.map((pred) {
            final predictionStr = pred.toString();
            final prediction = int.tryParse(predictionStr) ?? 0;
            return prediction == 1;
          }).toList();
        } else {
          throw Exception('No predictions received from GubatDetectAPI');
        }
      } else {
        throw Exception('Returned status code ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> processQueuedMessages() async {
    final queuedBox = Hive.box<QueuedMessage>('queued_messages');
    if (queuedBox.isEmpty) return;

    final inboxBox = Hive.box<SmsMessage>('inbox');
    final spamBox = Hive.box<SmsMessage>('spam');

    final queued = queuedBox.values.toList();
    final bodies = queued.map((q) => q.body).toList();

    try {
      final (spams, apiFailed) = await isSpamIsolate(bodies);

      if (apiFailed && SpamDetectionService.showOfflineSnackbar != null) {
        SpamDetectionService.showOfflineSnackbar!();
      }
      if (apiFailed) return;

      final Set<String> addressesToMarkAsSpam = {};
      for (var i = 0; i < queued.length; i++) {
        final queuedMsg = queued[i];
        final isSpamResult = spams[i];

        // Find the message in inbox by id
        final inboxMsg = inboxBox.values.where((m) => m.id == queuedMsg.id).firstOrNull;
        if (inboxMsg != null) {
          // If now classified as spam, move to spam
          if (isSpamResult) {
            await inboxMsg.delete();
            await spamBox.add(SmsMessage(
              address: inboxMsg.address,
              body: inboxMsg.body,
              date: inboxMsg.date,
              id: inboxMsg.id,
              isSpam: true,
            ));
            addressesToMarkAsSpam.add(inboxMsg.address);
          }
          // If not spam, leave in inbox (already isSpam=false)
        }
        // Remove from queued
        await queuedMsg.delete();
      }

      // Ensure all messages from spam addresses are marked as spam
      for (final address in addressesToMarkAsSpam) {
        await MessageProcessorIsolate.markConversationAsSpam(address);
      }
    } catch (e) {
      // If failed again, keep queued for later retry
    }
  }

  // Isolate entry point
  static void _detectSpamInIsolate(List<dynamic> args) async {
    final sendPort = args[0] as SendPort;
    final request = args[1] as SpamDetectionRequest;

    bool apiFailed = false;
    try {
      final encryptedMessages = await Future.wait(
        request.messages.map((msg) => _encryptMessageIsolate(msg, request.encryptionKey))
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
          final results = predictions.map((pred) {
            final predictionStr = pred.toString();
            final prediction = int.tryParse(predictionStr) ?? 0;
            return prediction == 1;
          }).toList();
          sendPort.send(SpamDetectionResponse(results, apiFailedDueToOffline: apiFailed));
        } else {
          apiFailed = true;
          sendPort.send(SpamDetectionResponse(List.filled(request.messages.length, false), apiFailedDueToOffline: apiFailed));
        }
      } else {
        apiFailed = true;
        sendPort.send(SpamDetectionResponse(List.filled(request.messages.length, false), apiFailedDueToOffline: apiFailed));
      }
    } catch (e) {
      apiFailed = true;
      sendPort.send(SpamDetectionResponse(List.filled(request.messages.length, false), apiFailedDueToOffline: apiFailed));
    }
  }

  // Encrypt in isolate
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

  // Public method to use isolate
  static Future<(List<bool>, bool)> isSpamIsolate(List<String> messages) async {
    final request = SpamDetectionRequest(messages, _apiUrl, _apiKey, _encryptionKey);
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(_detectSpamInIsolate, [receivePort.sendPort, request]);

    final response = await receivePort.first as SpamDetectionResponse;
    isolate.kill();
    return (response.results, response.apiFailedDueToOffline);
  }
}
