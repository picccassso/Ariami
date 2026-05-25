import 'package:shared_preferences/shared_preferences.dart';

/// Pre-loaded SharedPreferences for synchronous reads across the app.
late SharedPreferences sharedPrefs;

Future<void> initializeSharedPrefs() async {
  sharedPrefs = await SharedPreferences.getInstance();
}

/// Reload after a full prefs wipe so in-memory singleton state stays in sync.
Future<void> reloadSharedPrefs() async {
  sharedPrefs = await SharedPreferences.getInstance();
}
