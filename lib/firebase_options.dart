import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAiIw6nta_xLT_suXhXgjK7fpquPVzw9AU',
    appId: '1:100517014801:android:05a25b5842f605d3fb70b0',
    messagingSenderId: '100517014801',
    projectId: 'hookahorder-75e32',
    storageBucket: 'hookahorder-75e32.firebasestorage.app',
  );
}
