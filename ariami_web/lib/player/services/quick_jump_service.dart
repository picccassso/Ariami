import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool get _isApplePlatform => defaultTargetPlatform == TargetPlatform.macOS;

enum QuickJumpTriggerKey {
  primaryModifier,
  rightShift,
  alt,
  leftShift,
  control;

  String get id => name;

  String get label => switch (this) {
        QuickJumpTriggerKey.primaryModifier =>
          _isApplePlatform ? 'Command (⌘)' : 'Control (Ctrl)',
        QuickJumpTriggerKey.rightShift => 'Right Shift',
        QuickJumpTriggerKey.alt => _isApplePlatform ? 'Option (⌥)' : 'Alt',
        QuickJumpTriggerKey.leftShift => 'Left Shift',
        QuickJumpTriggerKey.control => 'Control',
      };

  static QuickJumpTriggerKey fromId(String? id) {
    return QuickJumpTriggerKey.values.firstWhere(
      (k) => k.id == id,
      orElse: () => QuickJumpTriggerKey.primaryModifier,
    );
  }
}

/// Service managing Quick Jump state, preferences, and keyboard event routing.
class QuickJumpService extends ChangeNotifier {
  static final QuickJumpService _instance = QuickJumpService._internal();

  factory QuickJumpService() => _instance;

  QuickJumpService._internal();

  static const String quickJumpEnabledKey = 'quick_jump_enabled';
  static const String quickJumpTriggerKeyPref = 'quick_jump_trigger_key';
  static const Duration highlightDuration = Duration(milliseconds: 600);

  bool _initialized = false;
  bool _enabled = true;
  QuickJumpTriggerKey _triggerKey = QuickJumpTriggerKey.primaryModifier;

  bool _isActive = false;
  bool isSidebarOpen = true;
  bool isMultiSelecting = false;

  int? _highlightedIndex;
  Timer? _highlightTimer;

  List<VoidCallback> targets = const <VoidCallback>[];

  @visibleForTesting
  bool Function()? isTriggerPressedOverride;

  @visibleForTesting
  bool Function()? isEditingOverride;

  bool get enabled => _enabled;
  QuickJumpTriggerKey get triggerKey => _triggerKey;
  bool get isActive => _isActive;
  int? get highlightedIndex => _highlightedIndex;

  void triggerHighlight(int index) {
    _highlightTimer?.cancel();
    _highlightedIndex = index;
    notifyListeners();
    _highlightTimer = Timer(highlightDuration, () {
      _highlightedIndex = null;
      notifyListeners();
    });
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(quickJumpEnabledKey) ?? true;
      final savedTrigger = prefs.getString(quickJumpTriggerKeyPref);
      _triggerKey = QuickJumpTriggerKey.fromId(savedTrigger);
      _initialized = true;
    } catch (_) {
      _enabled = true;
      _triggerKey = QuickJumpTriggerKey.primaryModifier;
    }
    FocusManager.instance.addListener(_evaluateActive);
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    FocusManager.instance.removeListener(_evaluateActive);
    super.dispose();
  }

  @visibleForTesting
  void resetForTesting() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    _highlightedIndex = null;
    _initialized = false;
    _enabled = true;
    _triggerKey = QuickJumpTriggerKey.primaryModifier;
    _isActive = false;
    isSidebarOpen = true;
    isMultiSelecting = false;
    targets = const <VoidCallback>[];
    isTriggerPressedOverride = null;
    isEditingOverride = null;
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    _evaluateActive();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(quickJumpEnabledKey, value);
    } catch (_) {}
  }

  Future<void> setTriggerKey(QuickJumpTriggerKey key) async {
    if (_triggerKey == key) return;
    _triggerKey = key;
    _evaluateActive();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(quickJumpTriggerKeyPref, key.id);
    } catch (_) {}
  }

  bool isTriggerKeyPressed(QuickJumpTriggerKey key) {
    if (isTriggerPressedOverride != null) {
      return isTriggerPressedOverride!();
    }
    final keyboard = HardwareKeyboard.instance;
    switch (key) {
      case QuickJumpTriggerKey.primaryModifier:
        return _isApplePlatform
            ? keyboard.isMetaPressed
            : keyboard.isControlPressed;
      case QuickJumpTriggerKey.rightShift:
        return keyboard.isPhysicalKeyPressed(PhysicalKeyboardKey.shiftRight) ||
            keyboard.isLogicalKeyPressed(LogicalKeyboardKey.shiftRight);
      case QuickJumpTriggerKey.alt:
        return keyboard.isAltPressed;
      case QuickJumpTriggerKey.leftShift:
        return keyboard.isPhysicalKeyPressed(PhysicalKeyboardKey.shiftLeft) ||
            keyboard.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft);
      case QuickJumpTriggerKey.control:
        return keyboard.isControlPressed;
    }
  }

  bool _isEditing() {
    if (isEditingOverride != null) {
      return isEditingOverride!();
    }
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _evaluateActive() {
    final shouldBeActive = _enabled &&
        isSidebarOpen &&
        !isMultiSelecting &&
        !_isEditing() &&
        isTriggerKeyPressed(_triggerKey);
    if (_isActive != shouldBeActive) {
      _isActive = shouldBeActive;
      notifyListeners();
    }
  }

  bool handleKeyEvent(KeyEvent event) {
    _evaluateActive();

    if (!_isActive) {
      return false;
    }

    if (event is KeyDownEvent) {
      final digit = _extractDigit(event);
      if (digit != null && digit >= 1 && digit <= 9) {
        final targetIndex = digit - 1;
        if (targetIndex < targets.length) {
          triggerHighlight(targetIndex);
          targets[targetIndex]();
          return true;
        }
      }
    }

    return false;
  }

  int? _extractDigit(KeyEvent event) {
    final logical = event.logicalKey;
    final physical = event.physicalKey;

    if (logical == LogicalKeyboardKey.digit1 ||
        physical == PhysicalKeyboardKey.digit1 ||
        logical == LogicalKeyboardKey.numpad1 ||
        physical == PhysicalKeyboardKey.numpad1) {
      return 1;
    }
    if (logical == LogicalKeyboardKey.digit2 ||
        physical == PhysicalKeyboardKey.digit2 ||
        logical == LogicalKeyboardKey.numpad2 ||
        physical == PhysicalKeyboardKey.numpad2) {
      return 2;
    }
    if (logical == LogicalKeyboardKey.digit3 ||
        physical == PhysicalKeyboardKey.digit3 ||
        logical == LogicalKeyboardKey.numpad3 ||
        physical == PhysicalKeyboardKey.numpad3) {
      return 3;
    }
    if (logical == LogicalKeyboardKey.digit4 ||
        physical == PhysicalKeyboardKey.digit4 ||
        logical == LogicalKeyboardKey.numpad4 ||
        physical == PhysicalKeyboardKey.numpad4) {
      return 4;
    }
    if (logical == LogicalKeyboardKey.digit5 ||
        physical == PhysicalKeyboardKey.digit5 ||
        logical == LogicalKeyboardKey.numpad5 ||
        physical == PhysicalKeyboardKey.numpad5) {
      return 5;
    }
    if (logical == LogicalKeyboardKey.digit6 ||
        physical == PhysicalKeyboardKey.digit6 ||
        logical == LogicalKeyboardKey.numpad6 ||
        physical == PhysicalKeyboardKey.numpad6) {
      return 6;
    }
    if (logical == LogicalKeyboardKey.digit7 ||
        physical == PhysicalKeyboardKey.digit7 ||
        logical == LogicalKeyboardKey.numpad7 ||
        physical == PhysicalKeyboardKey.numpad7) {
      return 7;
    }
    if (logical == LogicalKeyboardKey.digit8 ||
        physical == PhysicalKeyboardKey.digit8 ||
        logical == LogicalKeyboardKey.numpad8 ||
        physical == PhysicalKeyboardKey.numpad8) {
      return 8;
    }
    if (logical == LogicalKeyboardKey.digit9 ||
        physical == PhysicalKeyboardKey.digit9 ||
        logical == LogicalKeyboardKey.numpad9 ||
        physical == PhysicalKeyboardKey.numpad9) {
      return 9;
    }
    return null;
  }
}
