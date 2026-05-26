import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the desktop host's optional transcode slot override.
class DesktopTranscodeSlotsService {
  static const String _prefsKey = 'transcode_slots';

  Future<TranscodeSlotsSnapshot> getSnapshot() async {
    final override = await getOverride();
    return TranscodeSlotsPolicy.resolveSnapshot(override: override);
  }

  Future<int?> getOverride() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_prefsKey)) {
      return null;
    }
    return prefs.getInt(_prefsKey);
  }

  Future<TranscodeSlotsSnapshot> setOverride(int? slots) async {
    if (slots != null) {
      TranscodeSlotsPolicy.validateSlots(slots);
    }

    final prefs = await SharedPreferences.getInstance();
    if (slots == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setInt(_prefsKey, slots);
    }

    return getSnapshot();
  }
}
