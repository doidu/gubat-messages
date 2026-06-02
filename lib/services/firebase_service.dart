import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> reportSpam(String messageContent) async {
    const int maxAttempts = 2;
    const Duration timeout = Duration(seconds: 3);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final reportsRef = _firestore.collection('spam_reports');

        // Use set() to prevent duplicates
        await reportsRef.doc().set({
          'message': messageContent,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(timeout);

        return true;
      } catch (e) {
        if (attempt == maxAttempts) {
          return false;
        }
        await Future.delayed(Duration(milliseconds: 500));
      }
    }

    return false;
  }
}
