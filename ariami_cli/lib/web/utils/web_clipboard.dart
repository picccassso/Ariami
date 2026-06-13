import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Copies [text] to the clipboard from the Flutter web UI.
///
/// The CLI dashboard is almost always served over plain `http://` on a LAN IP
/// or Tailscale address. In that (non-secure) context mobile browsers do not
/// expose the async Clipboard API, so `Clipboard.setData` / `navigator.clipboard`
/// silently fail — which is why "copy the pairing code" never worked on phones.
///
/// This tries, in order:
///   1. The async Clipboard API (works on https / localhost).
///   2. A hidden `<textarea>` + `document.execCommand('copy')` fallback that
///      works on insecure origins and older mobile browsers.
///   3. Flutter's own [Clipboard.setData] as a last resort.
///
/// Returns `true` when the text was copied successfully.
Future<bool> copyToClipboard(String text) async {
  if (web.window.isSecureContext) {
    try {
      await web.window.navigator.clipboard.writeText(text).toDart;
      return true;
    } catch (_) {
      // Fall through to the legacy fallback below.
    }
  }

  if (_legacyExecCommandCopy(text)) {
    return true;
  }

  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

/// Legacy clipboard copy using a temporary off-screen `<textarea>` and
/// `document.execCommand('copy')`. This is the only path that works reliably
/// on mobile Safari/Chrome when the page is served over insecure http.
bool _legacyExecCommandCopy(String text) {
  web.HTMLTextAreaElement? textarea;
  try {
    textarea = web.HTMLTextAreaElement()
      ..value = text
      ..setAttribute('readonly', '')
      ..setAttribute('contenteditable', 'true');
    textarea.style
      ..position = 'fixed'
      ..top = '0'
      ..left = '0'
      ..width = '1px'
      ..height = '1px'
      ..padding = '0'
      ..margin = '0'
      ..border = 'none'
      ..outline = 'none'
      ..boxShadow = 'none'
      ..background = 'transparent'
      ..opacity = '0';

    web.document.body?.appendChild(textarea);
    textarea.focus();
    textarea.select();
    // iOS Safari needs an explicit selection range to copy reliably.
    textarea.setSelectionRange(0, text.length);

    return web.document.execCommand('copy');
  } catch (_) {
    return false;
  } finally {
    textarea?.remove();
  }
}
