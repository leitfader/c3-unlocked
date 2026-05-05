import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class CollectionService extends ChangeNotifier {
  CollectionService._(this._prefs, this._collections);

  static const String storageKey = 'media_collections_v1';
  static const String watchLaterId = 'watch_later';
  static const String watchLaterTitle = 'Watch Later';
  static const String likedId = 'liked_videos';
  static const String likedTitle = 'Liked Videos';

  final SharedPreferences _prefs;
  List<MediaCollection> _collections;

  List<MediaCollection> get collections =>
      List<MediaCollection>.unmodifiable(_collections);

  MediaCollection get watchLater {
    return collectionById(watchLaterId) ?? _defaultWatchLater();
  }

  MediaCollection get liked {
    return collectionById(likedId) ?? _defaultLiked();
  }

  static Future<CollectionService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = _decodeCollections(prefs.getString(storageKey));
    final service = CollectionService._(prefs, _ensureDefaults(decoded));
    await service._persist();
    return service;
  }

  MediaCollection? collectionById(String id) {
    for (final collection in _collections) {
      if (collection.id == id) return collection;
    }
    return null;
  }

  bool isInWatchLater(String eventGuid) {
    return watchLater.contains(eventGuid);
  }

  bool isLiked(String eventGuid) {
    return liked.contains(eventGuid);
  }

  bool isInCollection(String collectionId, String eventGuid) {
    return collectionById(collectionId)?.contains(eventGuid) ?? false;
  }

  Future<void> toggleWatchLater(CccEvent event) async {
    if (isInWatchLater(event.guid)) {
      await removeFromCollection(watchLaterId, event.guid);
    } else {
      await addToCollection(watchLaterId, event);
    }
  }

  Future<void> toggleLiked(CccEvent event) async {
    if (isLiked(event.guid)) {
      await removeFromCollection(likedId, event.guid);
    } else {
      await addToCollection(likedId, event);
    }
  }

  Future<MediaCollection> createCollection(String title) async {
    final cleanTitle = title.trim().isEmpty
        ? 'Untitled collection'
        : title.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    final collection = MediaCollection(
      id: stableId('$cleanTitle:$now'),
      title: cleanTitle,
      events: const <CccEvent>[],
      createdAt: now,
      updatedAt: now,
    );
    _collections = <MediaCollection>[collection, ..._collections];
    _sort();
    await _persistAndNotify();
    return collection;
  }

  Future<void> addToCollection(String collectionId, CccEvent event) async {
    final index = _collections.indexWhere(
      (collection) => collection.id == collectionId,
    );
    if (index < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final collection = _collections[index];
    final events = <CccEvent>[
      event,
      ...collection.events.where((item) => item.guid != event.guid),
    ];
    final next = <MediaCollection>[..._collections];
    next[index] = collection.copyWith(events: events, updatedAt: now);
    _collections = next;
    _sort();
    await _persistAndNotify();
  }

  Future<void> removeFromCollection(
    String collectionId,
    String eventGuid,
  ) async {
    final index = _collections.indexWhere(
      (collection) => collection.id == collectionId,
    );
    if (index < 0) return;
    final collection = _collections[index];
    final events = collection.events
        .where((event) => event.guid != eventGuid)
        .toList(growable: false);
    final next = <MediaCollection>[..._collections];
    next[index] = collection.copyWith(
      events: events,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _collections = next;
    _sort();
    await _persistAndNotify();
  }

  Future<void> deleteCollection(String collectionId) async {
    if (collectionId == watchLaterId || collectionId == likedId) return;
    _collections = _collections
        .where((collection) => collection.id != collectionId)
        .toList(growable: false);
    await _persistAndNotify();
  }

  Future<void> _persistAndNotify() async {
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _prefs.setString(
      storageKey,
      jsonEncode(
        _collections
            .map((collection) => collection.toJson())
            .toList(growable: false),
      ),
    );
  }

  void _sort() {
    _collections.sort((a, b) {
      final aRank = _defaultRank(a.id);
      final bRank = _defaultRank(b.id);
      if (aRank != bRank) return aRank.compareTo(bRank);
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }
}

List<MediaCollection> _decodeCollections(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <MediaCollection>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <MediaCollection>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(MediaCollection.fromJson)
        .where((collection) => collection.id.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const <MediaCollection>[];
  }
}

List<MediaCollection> _ensureDefaults(List<MediaCollection> collections) {
  final existing = <MediaCollection>[...collections];
  if (!existing.any(
    (collection) => collection.id == CollectionService.watchLaterId,
  )) {
    existing.insert(0, _defaultWatchLater());
  }
  if (!existing.any(
    (collection) => collection.id == CollectionService.likedId,
  )) {
    existing.insert(1, _defaultLiked());
  }
  existing.sort((a, b) {
    final aRank = _defaultRank(a.id);
    final bRank = _defaultRank(b.id);
    if (aRank != bRank) return aRank.compareTo(bRank);
    return b.updatedAt.compareTo(a.updatedAt);
  });
  return existing;
}

int _defaultRank(String id) {
  if (id == CollectionService.watchLaterId) return 0;
  if (id == CollectionService.likedId) return 1;
  return 2;
}

MediaCollection _defaultWatchLater() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return MediaCollection(
    id: CollectionService.watchLaterId,
    title: CollectionService.watchLaterTitle,
    events: const <CccEvent>[],
    createdAt: now,
    updatedAt: now,
  );
}

MediaCollection _defaultLiked() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return MediaCollection(
    id: CollectionService.likedId,
    title: CollectionService.likedTitle,
    events: const <CccEvent>[],
    createdAt: now,
    updatedAt: now,
  );
}
