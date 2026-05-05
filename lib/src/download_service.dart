import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_manager.dart';
import 'models.dart';

class DownloadService extends ChangeNotifier {
  DownloadService._(this._prefs, this._native, this._records);

  static const String _recordsKey = 'download_records_v1';

  final SharedPreferences _prefs;
  final NativeDownloadManager _native;
  List<DownloadRecord> _records;
  Timer? _pollTimer;

  List<DownloadRecord> get records =>
      List<DownloadRecord>.unmodifiable(_records);

  static Future<DownloadService> create({
    NativeDownloadManager native = const NativeDownloadManager(),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final service = DownloadService._(
      prefs,
      native,
      _decodeRecords(prefs.getString(_recordsKey)),
    );
    await service.reconcile();
    service._startPolling();
    return service;
  }

  DownloadRecord? recordById(String id) {
    for (final record in _records) {
      if (record.id == id) return record;
    }
    return null;
  }

  DownloadRecord? recordForRecording(String eventGuid, Recording recording) {
    return recordById(downloadRecordId(eventGuid, recording));
  }

  Future<DownloadRecord> queue({
    required CccEvent event,
    required Recording recording,
  }) async {
    final existing = recordForRecording(event.guid, recording);
    if (existing != null && existing.state != DownloadState.failed) {
      if (existing.isCompleted && !_hasLocalFile(existing)) {
        await remove(existing.id, deleteFile: false);
      } else {
        return existing;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = downloadRecordId(event.guid, recording);
    final conferenceTitle = event.conferenceTitle ?? 'media.ccc.de';
    final initial = DownloadRecord(
      id: id,
      eventGuid: event.guid,
      eventTitle: event.displayTitle,
      conferenceTitle: conferenceTitle,
      conferenceAcronym: event.conferenceAcronym,
      recording: recording,
      state: DownloadState.running,
      totalBytes: _estimatedBytes(recording),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    _upsert(initial);
    await _persist();

    try {
      final snapshot = await _native.enqueue(
        id: id,
        url: recording.recordingUrl,
        title: event.displayTitle,
        fileName: recording.filename,
        relativeDir: sanitizeFilePart(conferenceTitle),
        mimeType: recording.mimeType,
      );
      final next = _recordFromSnapshot(initial, snapshot);
      _upsert(next);
      await _persist();
      return next;
    } catch (error) {
      final failed = initial.copyWith(
        state: DownloadState.failed,
        errorMessage: error.toString(),
        keepErrorMessage: false,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _upsert(failed);
      await _persist();
      return failed;
    }
  }

  Future<void> retry(String id) async {
    final record = recordById(id);
    if (record == null) return;
    await remove(id, deleteFile: true);
    final event = CccEvent(
      guid: record.eventGuid,
      title: record.eventTitle,
      conferenceTitle: record.conferenceTitle,
      conferenceUrl:
          'https://api.media.ccc.de/public/conferences/${record.conferenceAcronym}',
      recordings: <Recording>[record.recording],
    );
    await queue(event: event, recording: record.recording);
  }

  Future<void> remove(String id, {bool deleteFile = true}) async {
    final record = recordById(id);
    if (record == null) return;
    try {
      await _native.remove(id);
    } catch (_) {}
    if (deleteFile && record.localPath != null) {
      final file = File(record.localPath!);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    _records = _records.where((item) => item.id != id).toList(growable: false);
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    final ids = _records.map((record) => record.id).toList(growable: false);
    for (final id in ids) {
      await remove(id);
    }
  }

  Future<bool> openExternal(String id) async {
    final record = recordById(id);
    final localPath = record?.localPath;
    if (record == null || localPath == null || !_hasLocalFile(record)) {
      return false;
    }
    return _native.openFile(localPath, record.recording.mimeType);
  }

  Future<void> reconcile() async {
    final ids = _records
        .where((record) => record.isActive || record.localPath == null)
        .map((record) => record.id)
        .toList(growable: false);
    final snapshots = await _native.queryAll(ids);
    final byId = <String, NativeDownloadSnapshot>{
      for (final snapshot in snapshots) snapshot.id: snapshot,
    };

    var changed = false;
    _records = _records
        .map((record) {
          final snapshot = byId[record.id];
          if (snapshot == null) {
            if (!record.isActive) return record;
            changed = true;
            return record.copyWith(
              state: DownloadState.failed,
              errorMessage: 'Download interrupted.',
              keepErrorMessage: false,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );
          }

          final next = _recordFromSnapshot(record, snapshot);
          if (!_sameDownloadState(record, next)) changed = true;
          return next;
        })
        .toList(growable: false);

    _sort();
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_records.any((record) => record.isActive)) {
        unawaited(reconcile());
      }
    });
  }

  DownloadRecord _recordFromSnapshot(
    DownloadRecord record,
    NativeDownloadSnapshot snapshot,
  ) {
    var state = snapshot.state;
    if (state == DownloadState.completed) {
      final localPath = snapshot.localPath ?? record.localPath;
      if (localPath == null || !File(localPath).existsSync()) {
        state = DownloadState.missing;
      }
    }
    return record.copyWith(
      state: state,
      bytesDownloaded: snapshot.bytesDownloaded,
      totalBytes: snapshot.totalBytes > 0
          ? snapshot.totalBytes
          : record.totalBytes,
      localPath: snapshot.localPath,
      keepLocalPath: snapshot.localPath == null,
      errorMessage: snapshot.reason,
      keepErrorMessage: snapshot.reason == null,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool _sameDownloadState(DownloadRecord a, DownloadRecord b) {
    return a.state == b.state &&
        a.bytesDownloaded == b.bytesDownloaded &&
        a.totalBytes == b.totalBytes &&
        a.localPath == b.localPath &&
        a.errorMessage == b.errorMessage;
  }

  bool _hasLocalFile(DownloadRecord record) {
    final localPath = record.localPath;
    return localPath != null && File(localPath).existsSync();
  }

  void _upsert(DownloadRecord record) {
    final index = _records.indexWhere((item) => item.id == record.id);
    if (index >= 0) {
      final next = <DownloadRecord>[..._records];
      next[index] = record;
      _records = next;
    } else {
      _records = <DownloadRecord>[record, ..._records];
    }
    _sort();
    notifyListeners();
  }

  void _sort() {
    _records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _persist() async {
    final raw = jsonEncode(
      _records.map((record) => record.toJson()).toList(growable: false),
    );
    await _prefs.setString(_recordsKey, raw);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

String downloadRecordId(String eventGuid, Recording recording) {
  return stableId('$eventGuid:${recording.id}:${recording.recordingUrl}');
}

int _estimatedBytes(Recording recording) {
  if (recording.sizeMb <= 0) return 0;
  return (recording.sizeMb * 1024 * 1024).round();
}

List<DownloadRecord> _decodeRecords(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <DownloadRecord>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <DownloadRecord>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DownloadRecord.fromJson)
        .where((record) => record.id.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const <DownloadRecord>[];
  }
}
