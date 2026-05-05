import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ProgressService extends ChangeNotifier {
  ProgressService._(this._prefs, this._entries);

  static const String _key = 'playback_progress_v1';
  static const int _maxEntries = 300;
  static const int _minPositionMs = 5000;
  static const int _completeToleranceMs = 30000;

  final SharedPreferences _prefs;
  List<PlaybackProgressEntry> _entries;

  static Future<ProgressService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _decode(prefs.getString(_key));
    return ProgressService._(prefs, entries);
  }

  PlaybackProgressEntry? find(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  int? percent(String id) {
    final entry = find(id);
    if (entry == null || entry.durationMs == null || entry.durationMs! <= 0) {
      return null;
    }
    return min(99, (entry.positionMs / entry.durationMs! * 100).round());
  }

  Future<void> save({
    required String id,
    required int positionMs,
    required int durationMs,
  }) async {
    final next = _entries
        .where((entry) => entry.id != id)
        .toList(growable: true);
    if (positionMs >= _minPositionMs &&
        durationMs - positionMs > _completeToleranceMs) {
      next.add(
        PlaybackProgressEntry(
          id: id,
          positionMs: positionMs,
          durationMs: durationMs > 0 ? durationMs : null,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _entries = next.take(_maxEntries).toList(growable: false);
    await _persist();
  }

  Future<void> clear(String id) async {
    _entries = _entries
        .where((entry) => entry.id != id)
        .toList(growable: false);
    await _persist();
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _key,
      jsonEncode(
        _entries.map((entry) => entry.toJson()).toList(growable: false),
      ),
    );
    notifyListeners();
  }
}

List<PlaybackProgressEntry> _decode(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <PlaybackProgressEntry>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <PlaybackProgressEntry>[];
    final entries = decoded
        .whereType<Map<String, dynamic>>()
        .map(PlaybackProgressEntry.fromJson)
        .where((entry) => entry.id.isNotEmpty)
        .toList(growable: false);
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  } catch (_) {
    return const <PlaybackProgressEntry>[];
  }
}
