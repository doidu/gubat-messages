# Gubat Messages

A spam-filtering SMS application built with Flutter. Gubat Messages helps users manage their text messages by automatically filtering out spam while keeping important messages secure with local encryption. To be used with Gubat Server.

## 🌟 Features

- **Spam Filtering**: Automatically detects and filters spam SMS messages.
- **Encrypted Local Storage**: Uses Hive with AES encryption to securely store inbox, spam, queued messages, and blocked numbers locally on the device.
- **Firebase Integration**: Syncs data and configurations using Cloud Firestore.
- **Contact Integration**: Seamlessly integrates with device contacts for better message identification.
- **Local Notifications**: Alerts users of new important messages even when the app is in the background.
- **Permission Management**: Guided permission setup to ensure smooth access to SMS, contacts, and notifications.

## 🛠️ Tech Stack

- **Framework**: Flutter (Dart)
- **Local Storage**: `hive` & `hive_flutter` (with AES encryption via `cryptography_plus`)
- **Backend**: Firebase (`firebase_core`, `cloud_firestore`)
- **SMS Handling**: `another_telephony`
- **Permissions**: `permission_handler`
- **Notifications**: `flutter_local_notifications`
- **Contacts**: `fast_contacts`
- **Environment Management**: `flutter_dotenv`

## 📋 Prerequisites

Before you begin, ensure you have the following installed:
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (>=3.0.0 <4.0.0)
- [Dart SDK](https://dart.dev/get-dart)
- [Android Studio](https://developer.android.com/studio) or VS Code with Flutter extensions
- A Firebase project configured for Android

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/gubat-messages.git
cd gubat-messages
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Firebase Setup

1. Go to your [Firebase Console](https://console.firebase.google.com/).
2. Add an Android app to your project and download the `google-services.json` file.
3. Place the `google-services.json` file in the `android/app/` directory.
4. Run the following command to generate Firebase options for Flutter:
   ```bash
   flutterfire configure
   ```
   *(Alternatively, ensure `lib/firebase_options.dart` is properly generated and configured).*

### 4. Environment Configuration

Create a `.env` file in the root directory of the project and add any required environment variables. For example:

```env
# Add your environment variables here
# EXAMPLE_API_KEY=your_api_key_here
```

### 5. Generate Hive Adapters

If you modify any Hive models, generate the adapter files using:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 6. Run the App

Connect an Android device or start an emulator, then run:

```bash
flutter run
```

## 📦 Building for Production

To build a release APK:

```bash
flutter build apk --release
```

To build an Android App Bundle (for Google Play Store):

```bash
flutter build appbundle --release
```

## 📁 Project Structure

```
lib/
├── main.dart                 # App entry point and initialization
├── firebase_options.dart     # Firebase configuration
├── models/                   # Data models (e.g., SmsMessage, QueuedMessage)
├── screens/                  # UI screens (e.g., PermissionScreen, Inbox, Spam)
├── services/                 # Business logic (e.g., SmsService, NotificationService)
├── utils/                    # Utility functions and helpers
└── widgets/                  # Reusable UI components
```

## 📄 License

This project is proprietary. Please refer to the repository owner for licensing details.

## 📞 Contact

For any inquiries or support, please reach out to the project maintainer or open an issue in the repository.