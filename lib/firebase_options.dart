// File generated from the approved Yingjian Firebase project configuration.
// ignore_for_file: type=lint

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for '
          '$defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyArwn06YgVzJqKPbvF_HbHdYpWcIFDRSp8',
    appId: '1:686956579548:android:a4928934bd0136bb768219',
    messagingSenderId: '686956579548',
    projectId: 'yingjian-ce1d1',
    storageBucket: 'yingjian-ce1d1.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB-e67IAAkUX5kbplrdW4sFvax76ybGl0c',
    appId: '1:686956579548:ios:ebc127341279f004768219',
    messagingSenderId: '686956579548',
    projectId: 'yingjian-ce1d1',
    storageBucket: 'yingjian-ce1d1.firebasestorage.app',
    iosBundleId: 'com.babycompany.yingjian',
  );
}
