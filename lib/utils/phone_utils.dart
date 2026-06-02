/// Utility functions for phone number handling
class PhoneUtils {
  /// Checks if a phone number is valid for Philippine numbers
  static bool isValidPhilippineNumber(String phoneNumber) {
    if (phoneNumber.isEmpty) return false;

    // Should be +63 followed by 10 digits
    if (!phoneNumber.startsWith('+63')) return false;
    if (phoneNumber.length != 13) return false; // +63 + 10 digits

    // Check if the remaining digits are valid
    String digits = phoneNumber.substring(3);
    return RegExp(r'^\d{10}$').hasMatch(digits);
  }
}
