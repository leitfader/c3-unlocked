import 'dart:io';

import 'package:flutter/services.dart';

import 'models.dart';

class NativeDownloadSnapshot {
  const NativeDownloadSnapshot({
    required this.id,
    required this.state,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.localPath,
    this.reason,
  });

  final String id;
  final DownloadState state;
  final int bytesDownloaded;
  final int totalBytes;
  final String? localPath;
  final String? reason;

  factory NativeDownloadSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return NativeDownloadSnapshot(
      id: map['id']?.toString() ?? '',
      state: _nativeState(map['state']?.toString()),
      bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      localPath: map['localPath']?.toString(),
      reason: map['reason']?.toString(),
    );
  }
}

class NativeDownloadManager {
  const NativeDownloadManager();

  static const MethodChannel _channel = MethodChannel('c3_unlocked/downloads');

  Future<NativeDownloadSnapshot> enqueue({
    required String id,
    required String url,
    required String title,
    required String fileName,
    required String relativeDir,
    required String mimeType,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'enqueueDownload',
      <String, dynamic>{
        'id': id,
        'url': url,
        'title': title,
        'fileName': fileName,
        'relativeDir': relativeDir,
        'mimeType': mimeType,
      },
    );
    if (raw == null || raw.isEmpty) {
      throw StateError('Android download service did not return a task.');
    }
    return NativeDownloadSnapshot.fromMap(raw);
  }

  Future<NativeDownloadSnapshot?> query(String id) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'queryDownload',
      <String, dynamic>{'id': id},
    );
    if (raw == null || raw.isEmpty) return null;
    return NativeDownloadSnapshot.fromMap(raw);
  }

  Future<List<NativeDownloadSnapshot>> queryAll(List<String> ids) async {
    if (ids.isEmpty) return const <NativeDownloadSnapshot>[];
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'queryDownloads',
      <String, dynamic>{'ids': ids},
    );
    if (raw == null) return const <NativeDownloadSnapshot>[];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(NativeDownloadSnapshot.fromMap)
        .where((snapshot) => snapshot.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> remove(String id) async {
    await _channel.invokeMethod<void>('removeDownload', <String, dynamic>{
      'id': id,
    });
  }

  Future<String> downloadsDirectory() async {
    try {
      final path = await _channel.invokeMethod<String>('downloadsDirectory');
      if (path != null && path.trim().isNotEmpty) return path;
    } on MissingPluginException {
      return Directory('${Directory.current.path}/downloads').path;
    }
    return Directory('${Directory.current.path}/downloads').path;
  }

  Future<bool> openFile(String path, String mimeType) async {
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openFile',
        <String, dynamic>{'path': path, 'mimeType': mimeType},
      );
      return opened ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}

DownloadState _nativeState(String? value) {
  switch (value) {
    case 'pending':
      return DownloadState.queued;
    case 'running':
      return DownloadState.running;
    case 'paused':
      return DownloadState.paused;
    case 'completed':
      return DownloadState.completed;
    case 'failed':
      return DownloadState.failed;
    case 'missing':
      return DownloadState.missing;
    default:
      return DownloadState.failed;
  }
}
