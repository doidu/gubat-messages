import 'package:fast_contacts/fast_contacts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class ContactService {
  static final ContactService _instance = ContactService._internal();

  factory ContactService() {
    return _instance;
  }

  ContactService._internal();
  // Cache of normalized phone -> contact name
  final Map<String, String> _contactCache = {};

  Future<void> initialize([HiveAesCipher? cipher]) async {
    await Hive.openBox<String>('contacts', encryptionCipher: cipher);
    await _loadContacts();
  }

  Future<void> _loadContacts() async {
    final status = await Permission.contacts.status;
    if (!status.isGranted) {
      return;
    }

    try {
      final contacts = await FastContacts.getAllContacts();

      final contactBox = Hive.box<String>('contacts');
      await contactBox.clear();

      _contactCache.clear();

      for (final contact in contacts) {
        final displayName = contact.displayName;

        for (final phone in contact.phones) {
          final originalPhone = phone.number.trim();

          if (originalPhone.isNotEmpty) {
            await contactBox.put(originalPhone, displayName);
            _contactCache[originalPhone] = displayName;
          }
        }
      }
    } catch (e) {
      //
    }
  }

  String? getContactName(String phoneNumber) {
    return _contactCache[phoneNumber];
  }

  String getDisplayName(String phoneNumber) {
    final contactName = getContactName(phoneNumber);
    return contactName ?? phoneNumber;
  }

  Future<void> refreshContacts() async {
    await _loadContacts();
  }

  bool hasContact(String phoneNumber) {
    return _contactCache.containsKey(phoneNumber);
  }

  Set<String> getContactAddresses() {
    return _contactCache.keys.toSet();
  }
}
