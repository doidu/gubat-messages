import 'package:hive_flutter/hive_flutter.dart';
import 'sms_message.dart';

part 'queued_message.g.dart';

@HiveType(typeId: 1)
class QueuedMessage extends HiveObject {
  @HiveField(0)
  final String address;

  @HiveField(1)
  final String body;

  @HiveField(2)
  final int date;

  @HiveField(3)
  final int id;

  @HiveField(4)
  final int queuedAt; // Timestamp when queued for retry

  QueuedMessage({
    required this.address,
    required this.body,
    required this.date,
    required this.id,
    required this.queuedAt,
  });

  /// Convert to SmsMessage after classification
  /// This factory will be used after getting the classification result
  factory QueuedMessage.fromSmsMessage(SmsMessage smsMessage) {
    return QueuedMessage(
      address: smsMessage.address,
      body: smsMessage.body,
      date: smsMessage.date,
      id: smsMessage.id,
      queuedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
