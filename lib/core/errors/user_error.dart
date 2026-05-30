import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns a human-readable message for an exception. Use this anywhere you'd
/// otherwise show `$e` to the user — raw `Exception: ...` strings are a tell
/// of a coder UI, and we hide that here.
///
/// Unknown errors fall back to a generic message. The full original is still
/// available via `debugPrint(e)` for logging if you want it.
String humanizeError(Object e) {
  if (e is StateError) {
    if (e.message.contains('encryption key')) {
      return 'Encrypted session not ready — try re-opening the party.';
    }
    if (e.message.contains('Location permission')) {
      return 'Location permission is required for this.';
    }
    return _firstLine(e.message);
  }
  if (e is TimeoutException) {
    return 'That took too long — check your connection and try again.';
  }
  if (e is SocketException || e is HttpException) {
    return 'Network issue — you may be offline or the server is unreachable.';
  }
  if (e is PostgrestException) {
    final code = e.code;
    if (code == '23505') return 'That already exists.';
    if (code == 'PGRST116') return 'Item not found.';
    if (code == '42501') {
      return 'You don\'t have permission for that — make sure you\'re in '
          'the party.';
    }
    return _firstLine(e.message);
  }
  if (e is AuthException) {
    return _firstLine(e.message);
  }
  if (e is FormatException) {
    return 'That doesn\'t look right — check the format and try again.';
  }
  // Fallback: strip "Exception: " / "Error: " prefixes, take the first line.
  return _firstLine(e.toString());
}

String _firstLine(String s) {
  var t = s.trim();
  if (t.startsWith('Exception: ')) t = t.substring(11);
  if (t.startsWith('Bad state: ')) t = t.substring(11);
  final nl = t.indexOf('\n');
  if (nl > 0) t = t.substring(0, nl);
  return t.isEmpty ? 'Something went wrong.' : t;
}
