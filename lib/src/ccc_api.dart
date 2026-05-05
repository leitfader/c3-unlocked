import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';

class CccApiException implements Exception {
  const CccApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CccApiService {
  CccApiService({http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _baseUri = baseUri ?? Uri.parse('https://api.media.ccc.de/public');

  final http.Client _client;
  final Uri _baseUri;

  Future<List<CccConference>> fetchConferences() async {
    final json = await _getJson(_uri('/conferences'));
    final raw = json['conferences'];
    if (raw is! List) return const <CccConference>[];
    final conferences = raw
        .whereType<Map<String, dynamic>>()
        .map(CccConference.fromJson)
        .toList(growable: false);
    conferences.sort((a, b) {
      final released = (b.eventLastReleasedAt ?? DateTime(0)).compareTo(
        a.eventLastReleasedAt ?? DateTime(0),
      );
      return released == 0 ? a.title.compareTo(b.title) : released;
    });
    return conferences;
  }

  Future<ConferenceDetail> fetchConference(String acronym) async {
    final json = await _getJson(_uri('/conferences/$acronym'));
    final detail = ConferenceDetail.fromJson(json);
    final sorted = <CccEvent>[
      ...detail.events,
    ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    return ConferenceDetail(conference: detail.conference, events: sorted);
  }

  Future<List<CccEvent>> fetchRecentEvents() async {
    final json = await _getJson(_uri('/events/recent'));
    final raw = json['events'];
    if (raw is! List) return const <CccEvent>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(CccEvent.fromJson)
        .toList(growable: false);
  }

  Future<PageResult<CccEvent>> fetchEvents({int page = 1}) async {
    final response = await _get(
      _uri('/events', query: <String, String>{'page': '$page'}),
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final raw = decoded is Map<String, dynamic> ? decoded['events'] : null;
    final items = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(CccEvent.fromJson)
              .toList(growable: false)
        : const <CccEvent>[];
    return PageResult<CccEvent>(
      items: items,
      total: _parseHeaderInt(response.headers['total']),
      perPage: _parseHeaderInt(response.headers['per-page']),
      nextPage: _parseLinkPage(response.headers['link'], 'next'),
      lastPage: _parseLinkPage(response.headers['link'], 'last'),
    );
  }

  Future<List<CccEvent>> fetchRandomEvents({
    int samplePages = 4,
    int limit = 40,
  }) async {
    final first = await fetchEvents();
    final lastPage = max(1, first.lastPage ?? first.nextPage ?? 1);
    final random = Random();
    final pageCount = samplePages.clamp(1, lastPage).toInt();
    final pages = <int>{};
    while (pages.length < pageCount) {
      pages.add(1 + random.nextInt(lastPage));
    }

    final results = await Future.wait(
      pages.map(
        (page) => page == 1 ? Future.value(first) : fetchEvents(page: page),
      ),
    );
    final events = results
        .expand((result) => result.items)
        .toList(growable: false);
    final unique = _dedupeEvents(events);
    unique.shuffle(random);
    return unique.take(limit).toList(growable: false);
  }

  Future<List<CccEvent>> fetchPopularEvents({
    int samplePages = 8,
    int limit = 80,
  }) async {
    final first = await fetchEvents();
    final lastPage = max(1, first.lastPage ?? first.nextPage ?? 1);
    final pageCount = samplePages.clamp(1, lastPage).toInt();
    final pages = <int>{1};
    if (pageCount > 1) {
      for (var index = 0; index < pageCount; index++) {
        final page = 1 + ((lastPage - 1) * index / (pageCount - 1)).round();
        pages.add(page.clamp(1, lastPage).toInt());
      }
    }

    final results = await Future.wait(
      pages.map(
        (page) => page == 1 ? Future.value(first) : fetchEvents(page: page),
      ),
    );
    final events = results
        .expand((result) => result.items)
        .toList(growable: false);
    final unique = _dedupeEvents(events)..sort(_comparePopularFirst);
    return unique.take(limit).toList(growable: false);
  }

  Future<List<CccEvent>> searchEvents(String query) async {
    final json = await _getJson(
      _uri('/events/search', query: <String, String>{'q': query}),
    );
    final raw = json['events'];
    if (raw is! List) return const <CccEvent>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(CccEvent.fromJson)
        .toList(growable: false);
  }

  Future<CccEvent?> resolveEventLink(String rawLink) async {
    final raw = rawLink.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'c3-unlocked') {
      final id = _customLinkEventId(uri);
      if (id != null) {
        try {
          return fetchEvent(id);
        } catch (_) {}
      }
    }

    final host = uri.host.toLowerCase();
    if ((scheme == 'https' || scheme == 'http') &&
        host == 'media.ccc.de' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'v') {
      final slug = Uri.decodeComponent(uri.pathSegments[1]);
      final results = await searchEvents(slug);
      if (results.isEmpty) return null;
      final normalized = uri.replace(query: '', fragment: '').toString();
      for (final event in results) {
        final link = event.frontendLink;
        if (event.slug == slug ||
            (link != null &&
                Uri.tryParse(
                      link,
                    )?.replace(query: '', fragment: '').toString() ==
                    normalized)) {
          return event;
        }
      }
      return results.first;
    }

    if (!raw.contains('/') && raw.length >= 12) {
      try {
        return fetchEvent(raw);
      } catch (_) {}
    }
    return null;
  }

  Future<CccEvent> fetchEvent(String guid) async {
    final json = await _getJson(_uri('/events/$guid'));
    final event = CccEvent.fromJson(json);
    final sortedRecordings = <Recording>[...event.recordings]
      ..sort((a, b) {
        final mp4 = (b.isMp4Video ? 1 : 0) - (a.isMp4Video ? 1 : 0);
        if (mp4 != 0) return mp4;
        final video = (b.isVideo ? 1 : 0) - (a.isVideo ? 1 : 0);
        if (video != 0) return video;
        return Recording.compareBestFirst(a, b);
      });
    return CccEvent(
      guid: event.guid,
      title: event.title,
      subtitle: event.subtitle,
      slug: event.slug,
      description: event.description,
      persons: event.persons,
      tags: event.tags,
      duration: event.duration,
      date: event.date,
      releaseDate: event.releaseDate,
      thumbUrl: event.thumbUrl,
      posterUrl: event.posterUrl,
      frontendLink: event.frontendLink,
      conferenceTitle: event.conferenceTitle,
      conferenceUrl: event.conferenceUrl,
      originalLanguage: event.originalLanguage,
      viewCount: event.viewCount,
      recordings: sortedRecordings,
    );
  }

  Uri _uri(String path, {Map<String, String>? query}) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$basePath$path', queryParameters: query);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _get(uri);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const CccApiException('Unexpected API response');
    }
    return decoded;
  }

  Future<http.Response> _get(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: const <String, String>{'Accept': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CccApiException(
        'media.ccc.de returned HTTP ${response.statusCode}',
      );
    }
    return response;
  }
}

int? _parseHeaderInt(String? value) {
  if (value == null) return null;
  return int.tryParse(value);
}

int? _parseLinkPage(String? header, String rel) {
  if (header == null || header.trim().isEmpty) return null;
  final parts = header.split(',');
  for (final part in parts) {
    if (!part.contains('rel="$rel"')) continue;
    final match = RegExp(r'[?&]page=(\d+)').firstMatch(part);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
  return null;
}

List<CccEvent> _dedupeEvents(List<CccEvent> events) {
  final unique = <String, CccEvent>{};
  for (final event in events) {
    unique[event.guid] = event;
  }
  return unique.values.toList(growable: false);
}

int _comparePopularFirst(CccEvent a, CccEvent b) {
  final views = b.viewCount.compareTo(a.viewCount);
  if (views != 0) return views;
  final bDate = b.releaseDate ?? b.date ?? DateTime(0);
  final aDate = a.releaseDate ?? a.date ?? DateTime(0);
  return bDate.compareTo(aDate);
}

String? _customLinkEventId(Uri uri) {
  if (uri.host == 'event' && uri.pathSegments.isNotEmpty) {
    return Uri.decodeComponent(uri.pathSegments.first);
  }
  if (uri.host.isNotEmpty && uri.pathSegments.isEmpty) {
    return Uri.decodeComponent(uri.host);
  }
  if (uri.pathSegments.isNotEmpty) {
    return Uri.decodeComponent(uri.pathSegments.first);
  }
  return null;
}
