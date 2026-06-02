import 'package:hive_flutter/hive_flutter.dart';

part 'sms_message.g.dart';

@HiveType(typeId: 0)
class SmsMessage extends HiveObject {
  @HiveField(0)
  final String address;

  @HiveField(1)
  final String body;

  @HiveField(2)
  final int date;

  @HiveField(3)
  final int id;

  @HiveField(4)
  bool isSpam;

  SmsMessage({
    required this.address,
    required this.body,
    required this.date,
    required this.id,
    this.isSpam = false,
  });

  String get formattedDate {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(date);
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}
