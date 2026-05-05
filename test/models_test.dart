import 'package:c3_media/src/models.dart';
import 'package:c3_media/src/c3_theme.dart';
import 'package:c3_media/src/collection_service.dart';
import 'package:c3_media/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Recording labels prefer useful Android download details', () {
    final recording = Recording.fromJson(const <String, dynamic>{
      'url': 'https://api.media.ccc.de/public/recordings/42',
      'recording_url': 'https://cdn.media.ccc.de/events/test.mp4',
      'filename': 'test.mp4',
      'mime_type': 'video/mp4',
      'language': 'eng',
      'high_quality': true,
      'width': 1920,
      'height': 1080,
      'size': 512,
      'length': 3000,
    });

    expect(recording.id, '42');
    expect(recording.isMp4Video, isTrue);
    expect(recording.qualityLabel, '1080p MP4 EN 512 MB');
  });

  test('Event preferredMp4 chooses high quality MP4 over alternatives', () {
    final event = CccEvent.fromJson(const <String, dynamic>{
      'guid': 'abc',
      'title': 'Talk',
      'recordings': <Map<String, dynamic>>[
        <String, dynamic>{
          'url': 'https://api.media.ccc.de/public/recordings/1',
          'recording_url': 'https://cdn.media.ccc.de/events/test.webm',
          'filename': 'test.webm',
          'mime_type': 'video/webm',
          'height': 2160,
          'size': 1200,
        },
        <String, dynamic>{
          'url': 'https://api.media.ccc.de/public/recordings/2',
          'recording_url': 'https://cdn.media.ccc.de/events/test.mp4',
          'filename': 'test.mp4',
          'mime_type': 'video/mp4',
          'height': 720,
          'high_quality': true,
          'size': 400,
        },
      ],
    });

    expect(event.preferredMp4?.id, '2');
  });

  test('Event metadata supports popularity and language filtering', () {
    final event = CccEvent.fromJson(const <String, dynamic>{
      'guid': 'meta',
      'title': 'Metadata talk',
      'original_language': 'deu',
      'view_count': 5916,
      'recordings': <Map<String, dynamic>>[
        <String, dynamic>{
          'recording_url': 'https://cdn.media.ccc.de/events/meta.mp4',
          'filename': 'meta.mp4',
          'mime_type': 'video/mp4',
          'language': 'deu-eng-fra',
        },
      ],
    });

    expect(event.viewCount, 5916);
    expect(formatViews(event.viewCount), '5.9K views');
    expect(event.matchesLanguage('deu'), isTrue);
    expect(event.matchesLanguage('eng'), isTrue);
    expect(event.matchesLanguage('fra'), isTrue);
    expect(event.matchesLanguage('spa'), isFalse);

    final restored = CccEvent.fromStoredJson(event.toStoredJson());
    expect(restored.viewCount, 5916);
    expect(restored.originalLanguage, 'deu');
  });

  test('Download record ids are stable', () {
    final recording = Recording(
      id: '99',
      recordingUrl: 'https://cdn.media.ccc.de/talk.mp4',
      filename: 'talk.mp4',
      mimeType: 'video/mp4',
    );

    expect(stableId('event:99:https://cdn.media.ccc.de/talk.mp4'), isNotEmpty);
    expect(sanitizeFilePart('a/b:c* d'), 'a b c d');
    expect(
      downloadRecordStable('event', recording),
      downloadRecordStable('event', recording),
    );
  });

  test(
    'Collection service creates watch later and dedupes saved videos',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = await CollectionService.create();
      addTearDown(service.dispose);

      final event = CccEvent(
        guid: 'event-1',
        title: 'Future archives',
        conferenceTitle: '39C3',
        recordings: const <Recording>[
          Recording(
            id: 'mp4',
            recordingUrl: 'https://cdn.media.ccc.de/future.mp4',
            filename: 'future.mp4',
            mimeType: 'video/mp4',
            height: 1080,
          ),
        ],
      );

      expect(service.watchLater.title, CollectionService.watchLaterTitle);
      expect(service.liked.title, CollectionService.likedTitle);
      await service.toggleWatchLater(event);
      expect(service.isInWatchLater(event.guid), isTrue);
      await service.toggleWatchLater(event);
      expect(service.isInWatchLater(event.guid), isFalse);
      await service.toggleLiked(event);
      expect(service.isLiked(event.guid), isTrue);
      expect(
        service.collectionById(CollectionService.likedId)?.events,
        hasLength(1),
      );

      final custom = await service.createCollection('Night queue');
      await service.addToCollection(custom.id, event);
      await service.addToCollection(custom.id, event);

      final saved = service.collectionById(custom.id)!;
      expect(saved.events, hasLength(1));
      expect(saved.events.single.preferredMp4?.filename, 'future.mp4');
    },
  );

  testWidgets('core cards fit a compact Android viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final longEvent = CccEvent(
      guid: 'event',
      title:
          'A very long Chaos Communication Congress talk title that should not overflow the card layout',
      subtitle:
          'A dense subtitle with enough words to exercise two line truncation',
      persons: const <String>['A Very Long Speaker Name', 'Another Speaker'],
      conferenceTitle: '39C3: Power Cycles',
      duration: const Duration(minutes: 63),
      date: DateTime(2025, 12, 30),
      thumbUrl: 'https://static.media.ccc.de/logo.svg',
    );
    final conference = CccConference(
      acronym: '39c3',
      title: '39C3: Power Cycles with an intentionally long conference title',
      logoUrl: 'https://static.media.ccc.de/logo.svg',
      eventLastReleasedAt: DateTime(2026, 2, 3),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildC3Theme(),
        home: Scaffold(
          body: C3Background(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                EventCard(event: longEvent, onTap: () {}),
                const SizedBox(height: 10),
                ConferenceCard(conference: conference),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(EventCard), findsOneWidget);
    expect(find.byType(ConferenceCard), findsOneWidget);
  });
}

String downloadRecordStable(String eventGuid, Recording recording) {
  return stableId('$eventGuid:${recording.id}:${recording.recordingUrl}');
}
