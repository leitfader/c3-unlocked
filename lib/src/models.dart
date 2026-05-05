import 'dart:convert';

import 'package:intl/intl.dart';

class PageResult<T> {
  const PageResult({
    required this.items,
    this.total,
    this.perPage,
    this.nextPage,
    this.lastPage,
  });

  final List<T> items;
  final int? total;
  final int? perPage;
  final int? nextPage;
  final int? lastPage;
}

class CccConference {
  const CccConference({
    required this.acronym,
    required this.title,
    this.description,
    this.logoUrl,
    this.url,
    this.slug,
    this.eventLastReleasedAt,
  });

  final String acronym;
  final String title;
  final String? description;
  final String? logoUrl;
  final String? url;
  final String? slug;
  final DateTime? eventLastReleasedAt;

  factory CccConference.fromJson(Map<String, dynamic> json) {
    return CccConference(
      acronym: _string(json['acronym']),
      title: _string(json['title'], fallback: 'Untitled event'),
      description: _nullableString(json['description']),
      logoUrl: _nullableString(json['logo_url']),
      url: _nullableString(json['url']),
      slug: _nullableString(json['slug']),
      eventLastReleasedAt: _date(json['event_last_released_at']),
    );
  }
}

class ConferenceDetail {
  const ConferenceDetail({required this.conference, required this.events});

  final CccConference conference;
  final List<CccEvent> events;

  factory ConferenceDetail.fromJson(Map<String, dynamic> json) {
    return ConferenceDetail(
      conference: CccConference.fromJson(json),
      events: _list(json['events']).map(CccEvent.fromJson).toList(),
    );
  }
}

class CccEvent {
  const CccEvent({
    required this.guid,
    required this.title,
    this.subtitle,
    this.slug,
    this.description,
    this.persons = const <String>[],
    this.tags = const <String>[],
    this.duration,
    this.date,
    this.releaseDate,
    this.thumbUrl,
    this.posterUrl,
    this.frontendLink,
    this.conferenceTitle,
    this.conferenceUrl,
    this.originalLanguage,
    this.viewCount = 0,
    this.recordings = const <Recording>[],
  });

  final String guid;
  final String title;
  final String? subtitle;
  final String? slug;
  final String? description;
  final List<String> persons;
  final List<String> tags;
  final Duration? duration;
  final DateTime? date;
  final DateTime? releaseDate;
  final String? thumbUrl;
  final String? posterUrl;
  final String? frontendLink;
  final String? conferenceTitle;
  final String? conferenceUrl;
  final String? originalLanguage;
  final int viewCount;
  final List<Recording> recordings;

  String get displayTitle {
    final sub = subtitle?.trim();
    if (sub == null || sub.isEmpty) return title;
    return '$title: $sub';
  }

  String get speakerLine =>
      persons.where((p) => p.trim().isNotEmpty).join(', ');

  String get conferenceAcronym {
    final raw = conferenceUrl?.split('/').last.trim();
    return (raw == null || raw.isEmpty) ? 'media-ccc' : raw;
  }

  Set<String> get languageCodes {
    final codes = <String>{};
    codes.addAll(languageCodesFrom(originalLanguage));
    for (final recording in recordings) {
      codes.addAll(languageCodesFrom(recording.language));
    }
    return codes;
  }

  bool matchesLanguage(String language) {
    final normalized = language.toLowerCase().trim();
    return normalized.isEmpty ||
        normalized == 'all' ||
        languageCodes.contains(normalized);
  }

  Recording? get preferredMp4 {
    final mp4 = recordings.where((r) => r.isMp4Video).toList()
      ..sort(Recording.compareBestFirst);
    return mp4.isEmpty ? null : mp4.first;
  }

  factory CccEvent.fromJson(Map<String, dynamic> json) {
    return CccEvent(
      guid: _string(json['guid']),
      title: _string(json['title'], fallback: 'Untitled talk'),
      subtitle: _nullableString(json['subtitle']),
      slug: _nullableString(json['slug']),
      description: _nullableString(json['description']),
      persons: _stringList(json['persons']),
      tags: _stringList(json['tags']),
      duration: _duration(json['duration'] ?? json['length']),
      date: _date(json['date']),
      releaseDate: _date(json['release_date']),
      thumbUrl: _nullableString(json['thumb_url']),
      posterUrl: _nullableString(json['poster_url']),
      frontendLink: _nullableString(json['frontend_link']),
      conferenceTitle: _nullableString(json['conference_title']),
      conferenceUrl: _nullableString(json['conference_url']),
      originalLanguage: _nullableString(json['original_language']),
      viewCount: _int(json['view_count']),
      recordings: _list(json['recordings']).map(Recording.fromJson).toList(),
    );
  }

  Map<String, dynamic> toStoredJson() {
    return <String, dynamic>{
      'guid': guid,
      'title': title,
      'subtitle': subtitle,
      'slug': slug,
      'description': description,
      'persons': persons,
      'tags': tags,
      'durationSeconds': duration?.inSeconds,
      'date': date?.toIso8601String(),
      'releaseDate': releaseDate?.toIso8601String(),
      'thumbUrl': thumbUrl,
      'posterUrl': posterUrl,
      'frontendLink': frontendLink,
      'conferenceTitle': conferenceTitle,
      'conferenceUrl': conferenceUrl,
      'originalLanguage': originalLanguage,
      'viewCount': viewCount,
      'recordings': recordings
          .map((recording) => recording.toJson())
          .toList(growable: false),
    };
  }

  factory CccEvent.fromStoredJson(Map<String, dynamic> json) {
    return CccEvent(
      guid: _string(json['guid']),
      title: _string(json['title'], fallback: 'Untitled talk'),
      subtitle: _nullableString(json['subtitle']),
      slug: _nullableString(json['slug']),
      description: _nullableString(json['description']),
      persons: _stringList(json['persons']),
      tags: _stringList(json['tags']),
      duration: _duration(json['durationSeconds']),
      date: _date(json['date']),
      releaseDate: _date(json['releaseDate']),
      thumbUrl: _nullableString(json['thumbUrl']),
      posterUrl: _nullableString(json['posterUrl']),
      frontendLink: _nullableString(json['frontendLink']),
      conferenceTitle: _nullableString(json['conferenceTitle']),
      conferenceUrl: _nullableString(json['conferenceUrl']),
      originalLanguage: _nullableString(json['originalLanguage']),
      viewCount: _int(json['viewCount']),
      recordings: _list(
        json['recordings'],
      ).map(Recording.fromStoredJson).toList(),
    );
  }
}

class Recording {
  const Recording({
    required this.id,
    required this.recordingUrl,
    required this.filename,
    required this.mimeType,
    this.language,
    this.folder,
    this.highQuality = false,
    this.width = 0,
    this.height = 0,
    this.sizeMb = 0,
    this.lengthSeconds = 0,
  });

  final String id;
  final String recordingUrl;
  final String filename;
  final String mimeType;
  final String? language;
  final String? folder;
  final bool highQuality;
  final int width;
  final int height;
  final num sizeMb;
  final int lengthSeconds;

  bool get isVideo => mimeType.toLowerCase().startsWith('video/');
  bool get isAudio => mimeType.toLowerCase().startsWith('audio/');
  bool get isMp4Video => isVideo && mimeType.toLowerCase().contains('mp4');
  bool get isWebM => mimeType.toLowerCase().contains('webm');

  String get familyLabel {
    final mime = mimeType.toLowerCase();
    if (mime.contains('mp4')) return 'MP4';
    if (mime.contains('webm')) return 'WebM';
    if (mime.contains('opus')) return 'Opus';
    if (mime.contains('mpeg')) return 'MP3';
    if (mime.contains('pdf')) return 'PDF';
    if (mime.contains('srt')) return 'SRT';
    if (mime.contains('vtt')) return 'WebVTT';
    return mimeType.split('/').last.toUpperCase();
  }

  String get qualityLabel {
    final parts = <String>[];
    if (height > 0 && isVideo) parts.add('${height}p');
    parts.add(familyLabel);
    final lang = languageLabel(language);
    if (lang.isNotEmpty) parts.add(lang);
    if (sizeMb > 0) parts.add(formatMegabytes(sizeMb));
    return parts.join(' ');
  }

  factory Recording.fromJson(Map<String, dynamic> json) {
    final apiUrl = _nullableString(json['url']) ?? '';
    final recordingUrl = _string(json['recording_url']);
    return Recording(
      id: apiUrl.isNotEmpty ? apiUrl.split('/').last : stableId(recordingUrl),
      recordingUrl: recordingUrl,
      filename: _string(
        json['filename'],
        fallback: Uri.tryParse(recordingUrl)?.pathSegments.last ?? 'recording',
      ),
      mimeType: _string(
        json['mime_type'],
        fallback: 'application/octet-stream',
      ),
      language: _nullableString(json['language']),
      folder: _nullableString(json['folder']),
      highQuality: json['high_quality'] == true,
      width: _int(json['width']),
      height: _int(json['height']),
      sizeMb: json['size'] is num ? json['size'] as num : _int(json['size']),
      lengthSeconds: _int(json['length']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'recordingUrl': recordingUrl,
      'filename': filename,
      'mimeType': mimeType,
      'language': language,
      'folder': folder,
      'highQuality': highQuality,
      'width': width,
      'height': height,
      'sizeMb': sizeMb,
      'lengthSeconds': lengthSeconds,
    };
  }

  factory Recording.fromStoredJson(Map<String, dynamic> json) {
    return Recording(
      id: _string(json['id']),
      recordingUrl: _string(json['recordingUrl']),
      filename: _string(json['filename']),
      mimeType: _string(json['mimeType']),
      language: _nullableString(json['language']),
      folder: _nullableString(json['folder']),
      highQuality: json['highQuality'] == true,
      width: _int(json['width']),
      height: _int(json['height']),
      sizeMb: json['sizeMb'] is num
          ? json['sizeMb'] as num
          : _int(json['sizeMb']),
      lengthSeconds: _int(json['lengthSeconds']),
    );
  }

  static int compareBestFirst(Recording a, Recording b) {
    final high = (b.highQuality ? 1 : 0) - (a.highQuality ? 1 : 0);
    if (high != 0) return high;
    final height = b.height.compareTo(a.height);
    if (height != 0) return height;
    return b.sizeMb.compareTo(a.sizeMb);
  }
}

enum DownloadState {
  queued,
  running,
  paused,
  completed,
  failed,
  canceled,
  missing,
}

class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.eventGuid,
    required this.eventTitle,
    required this.conferenceTitle,
    required this.conferenceAcronym,
    required this.recording,
    required this.createdAt,
    required this.updatedAt,
    this.downloadManagerId,
    this.state = DownloadState.queued,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.localUri,
    this.localPath,
    this.errorMessage,
  });

  final String id;
  final String eventGuid;
  final String eventTitle;
  final String conferenceTitle;
  final String conferenceAcronym;
  final Recording recording;
  final int? downloadManagerId;
  final DownloadState state;
  final int bytesDownloaded;
  final int totalBytes;
  final String? localUri;
  final String? localPath;
  final String? errorMessage;
  final int createdAt;
  final int updatedAt;

  bool get isActive =>
      state == DownloadState.queued ||
      state == DownloadState.running ||
      state == DownloadState.paused;
  bool get isCompleted => state == DownloadState.completed;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (bytesDownloaded / totalBytes).clamp(0, 1).toDouble();
  }

  DownloadRecord copyWith({
    int? downloadManagerId,
    DownloadState? state,
    int? bytesDownloaded,
    int? totalBytes,
    String? localUri,
    String? localPath,
    String? errorMessage,
    bool keepLocalUri = true,
    bool keepLocalPath = true,
    bool keepErrorMessage = true,
    int? updatedAt,
  }) {
    return DownloadRecord(
      id: id,
      eventGuid: eventGuid,
      eventTitle: eventTitle,
      conferenceTitle: conferenceTitle,
      conferenceAcronym: conferenceAcronym,
      recording: recording,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      downloadManagerId: downloadManagerId ?? this.downloadManagerId,
      state: state ?? this.state,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      localUri: keepLocalUri ? (localUri ?? this.localUri) : localUri,
      localPath: keepLocalPath ? (localPath ?? this.localPath) : localPath,
      errorMessage: keepErrorMessage
          ? (errorMessage ?? this.errorMessage)
          : errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'eventGuid': eventGuid,
      'eventTitle': eventTitle,
      'conferenceTitle': conferenceTitle,
      'conferenceAcronym': conferenceAcronym,
      'recording': recording.toJson(),
      'downloadManagerId': downloadManagerId,
      'state': state.name,
      'bytesDownloaded': bytesDownloaded,
      'totalBytes': totalBytes,
      'localUri': localUri,
      'localPath': localPath,
      'errorMessage': errorMessage,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory DownloadRecord.fromJson(Map<String, dynamic> json) {
    final stateName = _string(
      json['state'],
      fallback: DownloadState.queued.name,
    );
    return DownloadRecord(
      id: _string(json['id']),
      eventGuid: _string(json['eventGuid']),
      eventTitle: _string(json['eventTitle'], fallback: 'Untitled talk'),
      conferenceTitle: _string(
        json['conferenceTitle'],
        fallback: 'media.ccc.de',
      ),
      conferenceAcronym: _string(
        json['conferenceAcronym'],
        fallback: 'media-ccc',
      ),
      recording: Recording.fromStoredJson(
        json['recording'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      downloadManagerId: (json['downloadManagerId'] as num?)?.toInt(),
      state: DownloadState.values.firstWhere(
        (value) => value.name == stateName,
        orElse: () => DownloadState.queued,
      ),
      bytesDownloaded: _int(json['bytesDownloaded']),
      totalBytes: _int(json['totalBytes']),
      localUri: _nullableString(json['localUri']),
      localPath: _nullableString(json['localPath']),
      errorMessage: _nullableString(json['errorMessage']),
      createdAt: _int(json['createdAt']),
      updatedAt: _int(json['updatedAt']),
    );
  }
}

class PlaybackProgressEntry {
  const PlaybackProgressEntry({
    required this.id,
    required this.positionMs,
    required this.updatedAt,
    this.durationMs,
  });

  final String id;
  final int positionMs;
  final int? durationMs;
  final int updatedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'updatedAt': updatedAt,
    };
  }

  factory PlaybackProgressEntry.fromJson(Map<String, dynamic> json) {
    return PlaybackProgressEntry(
      id: _string(json['id']),
      positionMs: _int(json['positionMs']),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      updatedAt: _int(json['updatedAt']),
    );
  }
}

class MediaCollection {
  const MediaCollection({
    required this.id,
    required this.title,
    required this.events,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final List<CccEvent> events;
  final int createdAt;
  final int updatedAt;

  bool contains(String eventGuid) {
    return events.any((event) => event.guid == eventGuid);
  }

  MediaCollection copyWith({
    String? title,
    List<CccEvent>? events,
    int? updatedAt,
  }) {
    return MediaCollection(
      id: id,
      title: title ?? this.title,
      events: events ?? this.events,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'events': events.map((event) => event.toStoredJson()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory MediaCollection.fromJson(Map<String, dynamic> json) {
    return MediaCollection(
      id: _string(json['id']),
      title: _string(json['title'], fallback: 'Untitled collection'),
      events: _list(json['events'])
          .map(CccEvent.fromStoredJson)
          .where((event) => event.guid.isNotEmpty)
          .toList(growable: false),
      createdAt: _int(json['createdAt']),
      updatedAt: _int(json['updatedAt']),
    );
  }
}

String formatDate(DateTime? value) {
  if (value == null) return '';
  return DateFormat('yyyy-MM-dd').format(value.toLocal());
}

String formatDuration(Duration? duration) {
  if (duration == null) return '';
  final minutes = duration.inMinutes;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

String formatBytes(int bytes) {
  if (bytes <= 0) return 'Unknown size';
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String formatMegabytes(num megabytes) {
  if (megabytes >= 1024) {
    return '${(megabytes / 1024).toStringAsFixed(1)} GB';
  }
  return '${megabytes.round()} MB';
}

String formatViews(int views) {
  if (views >= 1000000) {
    final compact = views / 1000000;
    return '${compact.toStringAsFixed(compact >= 10 ? 0 : 1)}M views';
  }
  if (views >= 1000) {
    final compact = views / 1000;
    return '${compact.toStringAsFixed(compact >= 10 ? 0 : 1)}K views';
  }
  return views == 1 ? '1 view' : '$views views';
}

String languageLabel(String? language) {
  switch (language?.toLowerCase()) {
    case 'eng':
      return 'EN';
    case 'deu':
      return 'DE';
    case 'fra':
      return 'FR';
    case 'spa':
      return 'ES';
    case 'jpn':
      return 'JA';
    default:
      return language?.toUpperCase() ?? '';
  }
}

Set<String> languageCodesFrom(String? language) {
  final raw = language?.toLowerCase().trim();
  if (raw == null || raw.isEmpty) return const <String>{};
  return raw
      .split(RegExp(r'[-_,;/\s]+'))
      .where((code) => code.isNotEmpty)
      .toSet();
}

String sanitizeFilePart(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return 'media';
  return cleaned.length > 96 ? cleaned.substring(0, 96).trim() : cleaned;
}

String stableId(String input) {
  var hash = 0;
  for (final codeUnit in input.codeUnits) {
    hash = 0x1fffffff & (hash + codeUnit);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash ^= hash >> 11;
  hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  return hash.toRadixString(16);
}

List<Map<String, dynamic>> decodeJsonObjectList(String raw, String key) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) return const <Map<String, dynamic>>[];
  return _list(decoded[key]);
}

List<Map<String, dynamic>> _list(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw.whereType<Map<String, dynamic>>().toList(growable: false);
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((item) => item.toString())
      .where((item) => item.trim().isNotEmpty)
      .toList(growable: false);
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _date(Object? value) {
  final text = _nullableString(value);
  return text == null ? null : DateTime.tryParse(text);
}

Duration? _duration(Object? value) {
  final seconds = _int(value);
  return seconds <= 0 ? null : Duration(seconds: seconds);
}
