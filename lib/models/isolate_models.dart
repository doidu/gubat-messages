import 'dart:isolate';

// Data classes for isolate communication
class LoadMessagesRequest {
  final List<Map<String, dynamic>> messages;
  final Set<int> existingMessageIds;
  final Set<String> blockedNumbers;
  final Set<String> spamAddresses;
  final Set<String> contactAddresses;
  final SendPort sendPort;
  final String apiUrl;
  final String apiKey;
  final String encryptionKey;

  LoadMessagesRequest(this.messages, this.existingMessageIds, this.blockedNumbers, this.spamAddresses, this.contactAddresses, this.sendPort, this.apiUrl, this.apiKey, this.encryptionKey);
}

class LoadMessagesResponse {
  final List<Map<String, dynamic>> processedMessages;
  final List<Map<String, dynamic>> queuedMessages;
  final bool apiFailedDueToOffline;

  LoadMessagesResponse(this.processedMessages, this.queuedMessages, {this.apiFailedDueToOffline = false});
}

class IsolateMessage {
  final String type;
  final dynamic data;

  IsolateMessage(this.type, this.data);
}

class SpamDetectionRequest {
  final List<String> messages;
  final String apiUrl;
  final String apiKey;
  final String encryptionKey;
  SpamDetectionRequest(this.messages, this.apiUrl, this.apiKey, this.encryptionKey);
}

class SpamDetectionResponse {
  final List<bool> results;
  final bool apiFailedDueToOffline;
  SpamDetectionResponse(this.results, {this.apiFailedDueToOffline = false});
}

class ProcessIncomingResult {
  final bool isSpamDetected;
  final bool apiFailedDueToOffline;
  ProcessIncomingResult(this.isSpamDetected, {this.apiFailedDueToOffline = false});
}
