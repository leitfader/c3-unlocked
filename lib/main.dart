import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'src/c3_theme.dart';
import 'src/ccc_api.dart';
import 'src/collection_service.dart';
import 'src/download_service.dart';
import 'src/models.dart';
import 'src/progress_service.dart';
import 'src/widgets.dart';

const MethodChannel _linksChannel = MethodChannel('c3_unlocked/links');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp>
    with WidgetsBindingObserver {
  late final Future<AppServices> _services = AppServices.create();
  AppServices? _activeServices;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_activeServices?.downloads.reconcile());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeServices?.downloads.dispose();
    _activeServices?.collections.dispose();
    _activeServices?.progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _services,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildC3Theme(),
            scrollBehavior: const C3ScrollBehavior(),
            home: const Scaffold(
              body: C3Background(
                child: LoadingPanel(message: 'Booting c3-UNLOCKED'),
              ),
            ),
          );
        }
        final services = snapshot.data!;
        _activeServices = services;
        return MultiProvider(
          providers: [
            Provider<CccApiService>.value(value: services.api),
            ChangeNotifierProvider<DownloadService>.value(
              value: services.downloads,
            ),
            ChangeNotifierProvider<CollectionService>.value(
              value: services.collections,
            ),
            ChangeNotifierProvider<ProgressService>.value(
              value: services.progress,
            ),
          ],
          child: const C3MediaApp(),
        );
      },
    );
  }
}

class AppServices {
  const AppServices({
    required this.api,
    required this.downloads,
    required this.collections,
    required this.progress,
  });

  final CccApiService api;
  final DownloadService downloads;
  final CollectionService collections;
  final ProgressService progress;

  static Future<AppServices> create() async {
    return AppServices(
      api: CccApiService(),
      downloads: await DownloadService.create(),
      collections: await CollectionService.create(),
      progress: await ProgressService.create(),
    );
  }
}

class C3MediaApp extends StatefulWidget {
  const C3MediaApp({super.key});

  @override
  State<C3MediaApp> createState() => _C3MediaAppState();
}

class _C3MediaAppState extends State<C3MediaApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _initialLinkChecked = false;

  @override
  void initState() {
    super.initState();
    _linksChannel.setMethodCallHandler(_handleLinkCall);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialLinkChecked) return;
    _initialLinkChecked = true;
    unawaited(_openInitialLink());
  }

  @override
  void dispose() {
    _linksChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleLinkCall(MethodCall call) async {
    if (call.method == 'openLink') {
      final raw = call.arguments?.toString();
      if (raw != null && raw.trim().isNotEmpty) {
        await _openIncomingLink(raw);
      }
    }
  }

  Future<void> _openInitialLink() async {
    final String? raw;
    try {
      raw = await _linksChannel.invokeMethod<String>('initialLink');
    } on MissingPluginException {
      return;
    }
    if (raw == null || raw.trim().isEmpty) return;
    await _openIncomingLink(raw);
  }

  Future<void> _openIncomingLink(String raw) async {
    final api = context.read<CccApiService>();
    final videoEventId = _videoDeepLinkEventId(raw);
    if (videoEventId != null) {
      try {
        final event = await api.fetchEvent(videoEventId);
        if (!mounted) return;
        _navigatorKey.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => EventDetailScreen(initial: event),
          ),
        );
        return;
      } catch (_) {}
    }

    final directVideo = _directRecordingFromLink(raw);
    if (directVideo != null) {
      final event = directVideo.event;
      _navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(initial: event),
        ),
      );
      return;
    }

    final event = await api.resolveEventLink(raw);
    if (!mounted || event == null) return;
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(initial: event),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'c3-UNLOCKED',
      debugShowCheckedModeBanner: false,
      theme: buildC3Theme(),
      scrollBehavior: const C3ScrollBehavior(),
      navigatorKey: _navigatorKey,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = <Widget>[
    RandomBrowseScreen(),
    ConferencesScreen(),
    SearchScreen(),
    CollectionsScreen(),
    DownloadsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: C3Background(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const C3Header(title: 'c3-UNLOCKED', subtitle: 'by leitfader'),
              Expanded(child: _pages[_index]),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.shuffle), label: 'Random'),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_done),
            label: 'Downloads',
          ),
        ],
      ),
    );
  }
}

class RandomBrowseScreen extends StatefulWidget {
  const RandomBrowseScreen({super.key});

  @override
  State<RandomBrowseScreen> createState() => _RandomBrowseScreenState();
}

class _RandomBrowseScreenState extends State<RandomBrowseScreen> {
  late Future<List<CccEvent>> _future = _load();

  Future<List<CccEvent>> _load() =>
      context.read<CccApiService>().fetchRandomEvents();

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CccEvent>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingPanel(message: 'Shuffling the archive');
        }
        if (snapshot.hasError) {
          return ErrorPanel(
            message: snapshot.error.toString(),
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final events = snapshot.data ?? const <CccEvent>[];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: events.length + 2,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) return const SectionLabel('Random archive');
              if (index == 1) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _future = _load()),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Shuffle'),
                  ),
                );
              }
              final event = events[index - 2];
              return EventCard(
                event: event,
                onTap: () => _openEvent(context, event),
              );
            },
          ),
        );
      },
    );
  }
}

class ConferencesScreen extends StatefulWidget {
  const ConferencesScreen({super.key});

  @override
  State<ConferencesScreen> createState() => _ConferencesScreenState();
}

class _ConferencesScreenState extends State<ConferencesScreen> {
  final TextEditingController _filter = TextEditingController();
  late Future<List<CccConference>> _future = _load();

  Future<List<CccConference>> _load() =>
      context.read<CccApiService>().fetchConferences();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CccConference>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingPanel(message: 'Indexing events');
        }
        if (snapshot.hasError) {
          return ErrorPanel(
            message: snapshot.error.toString(),
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final all = snapshot.data ?? const <CccConference>[];
        return AnimatedBuilder(
          animation: _filter,
          builder: (context, _) {
            final query = _filter.text.trim().toLowerCase();
            final conferences = query.isEmpty
                ? all
                : all
                      .where(
                        (item) =>
                            item.title.toLowerCase().contains(query) ||
                            item.acronym.toLowerCase().contains(query),
                      )
                      .toList(growable: false);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: conferences.length + 2,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return TextField(
                    controller: _filter,
                    decoration: const InputDecoration(
                      hintText: 'Filter events',
                      prefixIcon: Icon(Icons.filter_alt_outlined),
                    ),
                  );
                }
                if (index == 1) return const SectionLabel('All events');
                final conference = conferences[index - 2];
                return ConferenceCard(
                  conference: conference,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConferenceScreen(conference: conference),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _query = TextEditingController();
  bool _loading = false;
  bool _popularFirst = false;
  String _language = 'all';
  String? _error;
  List<CccEvent> _results = const <CccEvent>[];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    final loadingPopularSample = query.isEmpty && _popularFirst;
    if (query.isEmpty && !loadingPopularSample) return;
    final api = context.read<CccApiService>();
    FocusManager.instance.primaryFocus?.unfocus();

    if (query.isNotEmpty && await _openPastedLink(query, api)) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = const <CccEvent>[];
    });
    try {
      final results = loadingPopularSample
          ? await api.fetchPopularEvents()
          : await api.searchEvents(query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _openPastedLink(String raw, CccApiService api) async {
    final videoEventId = _videoDeepLinkEventId(raw);
    if (videoEventId != null) {
      setState(() {
        _loading = true;
        _error = null;
        _results = const <CccEvent>[];
      });
      try {
        final event = await api.fetchEvent(videoEventId);
        if (!mounted) return true;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EventDetailScreen(initial: event),
          ),
        );
        return true;
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
        return true;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    final directVideo = _directRecordingFromLink(raw);
    if (directVideo != null) {
      final event = directVideo.event;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(initial: event),
        ),
      );
      return true;
    }

    if (!_looksLikeLink(raw)) return false;
    setState(() {
      _loading = true;
      _error = null;
      _results = const <CccEvent>[];
    });
    try {
      final event = await api.resolveEventLink(raw);
      if (!mounted) return true;
      if (event == null) {
        setState(() => _error = 'No media.ccc.de event found for that link.');
        return true;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(initial: event),
        ),
      );
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CccEvent> get _visibleResults {
    final results = _results
        .where((event) => event.matchesLanguage(_language))
        .toList(growable: false);
    if (!_popularFirst) return results;
    return [...results]..sort(_compareEventsByViews);
  }

  void _setPopularFirst(bool selected) {
    setState(() => _popularFirst = selected);
    if (selected && _query.text.trim().isEmpty && _results.isEmpty) {
      unawaited(_search());
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleResults = _visibleResults;
    if (!_loading && _error == null && _results.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: visibleResults.length + 2,
        separatorBuilder: (_, index) =>
            index < 1 ? const SizedBox(height: 12) : const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _SearchBar(
              controller: _query,
              loading: _loading,
              popularFirst: _popularFirst,
              language: _language,
              onSearch: _search,
              onPopularChanged: _setPopularFirst,
              onLanguageChanged: (value) => setState(() => _language = value),
            );
          }
          if (index == 1) {
            final label = _popularFirst
                ? '${visibleResults.length} matches by views'
                : '${visibleResults.length} matches';
            return SectionLabel(label);
          }
          final event = visibleResults[index - 2];
          return EventCard(
            event: event,
            onTap: () => _openEvent(context, event),
          );
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: <Widget>[
        _SearchBar(
          controller: _query,
          loading: _loading,
          popularFirst: _popularFirst,
          language: _language,
          onSearch: _search,
          onPopularChanged: _setPopularFirst,
          onLanguageChanged: (value) => setState(() => _language = value),
        ),
        if (_loading) ...const <Widget>[
          SizedBox(height: 48),
          LoadingPanel(message: 'Searching media.ccc.de'),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 24),
          ErrorPanel(message: _error!, onRetry: _search),
        ],
        if (!_loading && _error == null && _results.isEmpty) ...<Widget>[
          const SectionLabel('Search'),
          Text(
            _popularFirst
                ? 'Loading popular videos does not need a query.'
                : 'Query the public media.ccc.de event index.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.loading,
    required this.popularFirst,
    required this.language,
    required this.onSearch,
    required this.onPopularChanged,
    required this.onLanguageChanged,
  });

  final TextEditingController controller;
  final bool loading;
  final bool popularFirst;
  final String language;
  final VoidCallback onSearch;
  final ValueChanged<bool> onPopularChanged;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearch(),
                decoration: const InputDecoration(
                  hintText: 'Search talks, speakers, topics',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: loading ? null : onSearch,
              child: const Text('Go'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: language,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.translate),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: _languageFilters
                    .map(
                      (filter) => DropdownMenuItem<String>(
                        value: filter.code,
                        child: Text(
                          filter.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: loading
                    ? null
                    : (value) => onLanguageChanged(value ?? 'all'),
              ),
            ),
            const SizedBox(width: 10),
            FilterChip(
              selected: popularFirst,
              showCheckmark: false,
              avatar: const Icon(Icons.trending_up, size: 18),
              label: const Text('Popular'),
              onSelected: loading ? null : onPopularChanged,
            ),
          ],
        ),
      ],
    );
  }
}

const _languageFilters = <_LanguageFilter>[
  _LanguageFilter('all', 'All languages'),
  _LanguageFilter('eng', 'English'),
  _LanguageFilter('deu', 'German'),
  _LanguageFilter('fra', 'French'),
  _LanguageFilter('spa', 'Spanish'),
  _LanguageFilter('jpn', 'Japanese'),
];

class _LanguageFilter {
  const _LanguageFilter(this.code, this.label);

  final String code;
  final String label;
}

int _compareEventsByViews(CccEvent a, CccEvent b) {
  final views = b.viewCount.compareTo(a.viewCount);
  if (views != 0) return views;
  final bDate = b.releaseDate ?? b.date ?? DateTime(0);
  final aDate = a.releaseDate ?? a.date ?? DateTime(0);
  return bDate.compareTo(aDate);
}

class ConferenceScreen extends StatefulWidget {
  const ConferenceScreen({super.key, required this.conference});

  final CccConference conference;

  @override
  State<ConferenceScreen> createState() => _ConferenceScreenState();
}

class _ConferenceScreenState extends State<ConferenceScreen> {
  late Future<ConferenceDetail> _future = _load();

  Future<ConferenceDetail> _load() {
    return context.read<CccApiService>().fetchConference(
      widget.conference.acronym,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.conference.acronym)),
      body: C3Background(
        child: SafeArea(
          child: FutureBuilder<ConferenceDetail>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingPanel(message: 'Loading event program');
              }
              if (snapshot.hasError) {
                return ErrorPanel(
                  message: snapshot.error.toString(),
                  onRetry: () => setState(() => _future = _load()),
                );
              }
              final detail = snapshot.data!;
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: detail.events.length + 2,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ConferenceCard(conference: detail.conference);
                  }
                  if (index == 1) {
                    return SectionLabel('${detail.events.length} talks');
                  }
                  final event = detail.events[index - 2];
                  return EventCard(
                    event: event,
                    onTap: () => _openEvent(context, event),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CollectionService>(
      builder: (context, collections, _) {
        final items = collections.collections;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: items.length + 2,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _CreateCollectionButton(
                onCreate: () => _promptCreateCollection(context),
              );
            }
            if (index == 1) return const SectionLabel('Collections');
            final collection = items[index - 2];
            return _CollectionCard(collection: collection);
          },
        );
      },
    );
  }
}

class CollectionDetailScreen extends StatelessWidget {
  const CollectionDetailScreen({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context) {
    return Consumer<CollectionService>(
      builder: (context, collections, _) {
        final collection = collections.collectionById(collectionId);
        if (collection == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Collection')),
            body: const C3Background(
              child: Center(child: Text('Collection no longer exists.')),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(
              collection.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: <Widget>[
              if (collection.id != CollectionService.watchLaterId &&
                  collection.id != CollectionService.likedId)
                IconButton(
                  tooltip: 'Delete collection',
                  onPressed: () => _deleteCollection(context, collection),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: C3Background(
            child: SafeArea(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: collection.events.length + 2,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _CollectionSummary(collection: collection);
                  }
                  if (index == 1) {
                    return SectionLabel('${collection.events.length} videos');
                  }
                  final event = collection.events[index - 2];
                  return _SavedEventCard(
                    collectionId: collection.id,
                    event: event,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CreateCollectionButton extends StatelessWidget {
  const _CreateCollectionButton({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onCreate,
      icon: const Icon(Icons.add),
      label: const Text('New collection'),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.collection});

  final MediaCollection collection;

  @override
  Widget build(BuildContext context) {
    final latest = collection.events.isEmpty
        ? 'No videos saved yet'
        : collection.events.first.displayTitle;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CollectionDetailScreen(collectionId: collection.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Icon(
                collection.id == CollectionService.watchLaterId
                    ? Icons.playlist_add_check
                    : collection.id == CollectionService.likedId
                    ? Icons.favorite
                    : Icons.folder_outlined,
                color: c3Cyan,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      collection.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      latest,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MetricChip('${collection.events.length}'),
              const Icon(Icons.chevron_right, color: c3Muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionSummary extends StatelessWidget {
  const _CollectionSummary({required this.collection});

  final MediaCollection collection;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              collection.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '${collection.events.length} saved videos. Open a talk to download a local copy.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _ActionGrid(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => _promptCreateCollection(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New collection'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedEventCard extends StatelessWidget {
  const _SavedEventCard({required this.collectionId, required this.event});

  final String collectionId;
  final CccEvent event;

  @override
  Widget build(BuildContext context) {
    final preferred = event.preferredMp4;
    return Column(
      children: <Widget>[
        EventCard(event: event, onTap: () => _openEvent(context, event)),
        const SizedBox(height: 8),
        _ActionGrid(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: preferred == null
                  ? null
                  : () => _downloadRecording(context, event, preferred),
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
            OutlinedButton.icon(
              onPressed: () => context
                  .read<CollectionService>()
                  .removeFromCollection(collectionId, event.guid),
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 360 ? 2 : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.initial});

  final CccEvent initial;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late Future<CccEvent> _future = _load();

  Future<CccEvent> _load() =>
      context.read<CccApiService>().fetchEvent(widget.initial.guid);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Talk')),
      body: C3Background(
        child: SafeArea(
          child: FutureBuilder<CccEvent>(
            future: _future,
            builder: (context, snapshot) {
              final event = snapshot.data ?? widget.initial;
              if (snapshot.connectionState != ConnectionState.done &&
                  event.recordings.isEmpty) {
                return const LoadingPanel(message: 'Resolving recordings');
              }
              if (snapshot.hasError && event.recordings.isEmpty) {
                return ErrorPanel(
                  message: snapshot.error.toString(),
                  onRetry: () => setState(() => _future = _load()),
                );
              }
              return _EventDetailContent(event: event);
            },
          ),
        ),
      ),
    );
  }
}

class _EventDetailContent extends StatelessWidget {
  const _EventDetailContent({required this.event});

  final CccEvent event;

  @override
  Widget build(BuildContext context) {
    final preferred = event.preferredMp4;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: <Widget>[
        RemotePoster(
          url: event.posterUrl ?? event.thumbUrl,
          label: event.title,
          width: double.infinity,
          height: 210,
        ),
        const SizedBox(height: 14),
        Text(
          event.displayTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            if (event.conferenceTitle != null)
              MetricChip(event.conferenceTitle!),
            if (event.duration != null)
              MetricChip(formatDuration(event.duration), color: c3Lime),
            if (event.date != null)
              MetricChip(formatDate(event.date), color: c3Magenta),
            if (event.viewCount > 0)
              MetricChip(formatViews(event.viewCount), color: c3Amber),
            if (event.originalLanguage != null)
              MetricChip(languageLabel(event.originalLanguage), color: c3Muted),
            if (preferred != null)
              MetricChip(preferred.qualityLabel, color: c3Amber),
          ],
        ),
        if (event.speakerLine.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            event.speakerLine,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        const SizedBox(height: 16),
        Consumer<CollectionService>(
          builder: (context, collections, _) {
            final saved = collections.isInWatchLater(event.guid);
            final liked = collections.isLiked(event.guid);
            return _ActionGrid(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: preferred == null
                      ? null
                      : () => _playRecording(context, event, preferred),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play MP4'),
                ),
                OutlinedButton.icon(
                  onPressed: preferred == null
                      ? null
                      : () => _downloadRecording(context, event, preferred),
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
                OutlinedButton.icon(
                  onPressed: preferred == null
                      ? null
                      : () => _shareRecording(context, event, preferred),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share video'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _toggleLiked(context, event),
                  icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
                  label: Text(liked ? 'Liked' : 'Like'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _toggleWatchLater(context, event),
                  icon: Icon(
                    saved
                        ? Icons.playlist_add_check
                        : Icons.playlist_add_outlined,
                  ),
                  label: Text(saved ? 'Saved' : 'Watch later'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showCollectionPicker(context, event),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Collection'),
                ),
                OutlinedButton.icon(
                  onPressed: event.recordings.isEmpty
                      ? null
                      : () => _showRecordingPicker(context, event),
                  icon: const Icon(Icons.tune),
                  label: const Text('Formats'),
                ),
              ],
            );
          },
        ),
        if (event.description != null &&
            event.description!.trim().isNotEmpty) ...<Widget>[
          const SectionLabel('Description'),
          Text(
            event.description!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (event.tags.isNotEmpty) ...<Widget>[
          const SectionLabel('Tags'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: event.tags
                .take(24)
                .map((tag) => MetricChip(tag, color: c3Muted))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadService>(
      builder: (context, downloads, _) {
        final records = downloads.records;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            if (records.isEmpty) ...<Widget>[
              const SectionLabel('Downloads'),
              Text(
                'Downloaded talks stay inside c3-UNLOCKED for offline playback.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...<Widget>[
              SectionLabel('${records.length} local downloads'),
              ...records.map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DownloadCard(record: record),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class DownloadsRouteScreen extends StatelessWidget {
  const DownloadsRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: _PlainDownloadsAppBar(),
      body: C3Background(child: SafeArea(child: DownloadsScreen())),
    );
  }
}

class _PlainDownloadsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _PlainDownloadsAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('Downloads'));
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.record});

  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    final progressText = record.totalBytes > 0
        ? '${formatBytes(record.bytesDownloaded)} / ${formatBytes(record.totalBytes)}'
        : record.recording.sizeMb > 0
        ? formatMegabytes(record.recording.sizeMb)
        : 'Waiting for size';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  _stateIcon(record.state),
                  color: _stateColor(record.state),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        record.eventTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${record.conferenceTitle} - ${record.recording.qualityLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (record.isActive)
              LinearProgressIndicator(
                value: record.totalBytes > 0 ? record.progress : null,
              ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    progressText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                MetricChip(
                  record.state.name.toUpperCase(),
                  color: _stateColor(record.state),
                ),
              ],
            ),
            if (record.errorMessage != null &&
                record.errorMessage!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                record.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: record.isCompleted && record.localPath != null
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                PlaybackScreen.offline(record: record),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Watch'),
                ),
                if (record.state == DownloadState.failed ||
                    record.state == DownloadState.canceled)
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.read<DownloadService>().retry(record.id),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.read<DownloadService>().remove(record.id),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackScreen extends StatefulWidget {
  PlaybackScreen.online({
    super.key,
    required CccEvent event,
    required Recording recording,
  }) : title = event.displayTitle,
       sourceId = 'online:${event.guid}:${recording.id}',
       url = recording.recordingUrl,
       localPath = null,
       recordingLabel = recording.qualityLabel;

  PlaybackScreen.offline({super.key, required DownloadRecord record})
    : title = record.eventTitle,
      sourceId = 'offline:${record.id}',
      url = null,
      localPath = record.localPath,
      recordingLabel = record.recording.qualityLabel;

  final String title;
  final String sourceId;
  final String? url;
  final String? localPath;
  final String recordingLabel;

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  VideoPlayerController? _controller;
  late final ProgressService _progress;
  bool _ready = false;
  String? _error;
  Timer? _saveTimer;
  Timer? _hideControlsTimer;
  bool _fullscreen = false;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _progress = context.read<ProgressService>();
    unawaited(WakelockPlus.enable());
    unawaited(_initialize());
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    unawaited(_persist());
    _saveTimer?.cancel();
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    if (_fullscreen) unawaited(_setFullscreen(false));
    super.dispose();
  }

  Future<void> _initialize() async {
    final previous = _controller;
    _controller = null;
    _ready = false;
    _error = null;
    if (mounted) setState(() {});
    await previous?.dispose();
    try {
      final localPath = widget.localPath;
      final url = widget.url;
      final controller = localPath != null
          ? VideoPlayerController.file(File(localPath))
          : VideoPlayerController.networkUrl(Uri.parse(url!));
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      final progress = _progress.find(widget.sourceId);
      if (progress != null && progress.positionMs > 0) {
        await controller.seekTo(Duration(milliseconds: progress.positionMs));
        if (!mounted) return;
      }
      await controller.play();
      if (!mounted) return;
      controller.addListener(_onTick);
      _saveTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _persist(),
      );
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _persist() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await _progress.save(
      id: widget.sourceId,
      positionMs: controller.value.position.inMilliseconds,
      durationMs: controller.value.duration.inMilliseconds,
    );
  }

  Future<void> _setFullscreen(bool value) async {
    _fullscreen = value;
    if (value) {
      _controlsVisible = true;
      _scheduleFullscreenControlsHide();
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _hideControlsTimer?.cancel();
      _controlsVisible = true;
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) setState(() {});
  }

  void _scheduleFullscreenControlsHide() {
    _hideControlsTimer?.cancel();
    if (!_fullscreen) return;
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _fullscreen) setState(() => _controlsVisible = false);
    });
  }

  void _showFullscreenControls() {
    if (!_fullscreen) return;
    setState(() => _controlsVisible = true);
    _scheduleFullscreenControlsHide();
  }

  void _toggleFullscreenControls() {
    if (!_fullscreen) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleFullscreenControlsHide();
  }

  Future<void> _seekBy(Duration delta) async {
    final controller = _controller;
    if (controller == null) return;
    final duration = controller.value.duration;
    var target = controller.value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await controller.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = controller?.value;
    final initialized = value?.isInitialized ?? false;
    final position = value?.position ?? Duration.zero;
    final duration = value?.duration ?? Duration.zero;
    final max = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final current = position.inMilliseconds.clamp(0, max.toInt()).toDouble();

    final content = _error != null
        ? ErrorPanel(message: _error!, onRetry: _initialize)
        : !_ready || controller == null || !initialized
        ? const LoadingPanel(message: 'Opening player')
        : _fullscreen
        ? _FullscreenPlayer(
            controller: controller,
            title: widget.title,
            recordingLabel: widget.recordingLabel,
            controlsVisible: _controlsVisible,
            position: position,
            duration: duration,
            sliderValue: current,
            sliderMax: max,
            onTap: _toggleFullscreenControls,
            onShowControls: _showFullscreenControls,
            onSeek: (next) =>
                controller.seekTo(Duration(milliseconds: next.toInt())),
            onSeekBy: _seekBy,
            onTogglePlay: () =>
                value!.isPlaying ? controller.pause() : controller.play(),
            onExitFullscreen: () => _setFullscreen(false),
          )
        : _InlinePlayer(
            controller: controller,
            value: value!,
            title: widget.title,
            recordingLabel: widget.recordingLabel,
            position: position,
            duration: duration,
            sliderValue: current,
            sliderMax: max,
            onSeek: (next) =>
                controller.seekTo(Duration(milliseconds: next.toInt())),
            onSeekBy: _seekBy,
            onTogglePlay: () =>
                value.isPlaying ? controller.pause() : controller.play(),
            onEnterFullscreen: () => _setFullscreen(true),
          );

    return Scaffold(
      backgroundColor: c3Black,
      resizeToAvoidBottomInset: false,
      appBar: _fullscreen
          ? null
          : AppBar(
              title: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
      body: _fullscreen
          ? content
          : C3Background(child: SafeArea(child: content)),
    );
  }
}

class _InlinePlayer extends StatelessWidget {
  const _InlinePlayer({
    required this.controller,
    required this.value,
    required this.title,
    required this.recordingLabel,
    required this.position,
    required this.duration,
    required this.sliderValue,
    required this.sliderMax,
    required this.onSeek,
    required this.onSeekBy,
    required this.onTogglePlay,
    required this.onEnterFullscreen,
  });

  final VideoPlayerController controller;
  final VideoPlayerValue value;
  final String title;
  final String recordingLabel;
  final Duration position;
  final Duration duration;
  final double sliderValue;
  final double sliderMax;
  final ValueChanged<double> onSeek;
  final ValueChanged<Duration> onSeekBy;
  final VoidCallback onTogglePlay;
  final VoidCallback onEnterFullscreen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio <= 0 ? 16 / 9 : value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        _PlayerControls(
          title: title,
          recordingLabel: recordingLabel,
          position: position,
          duration: duration,
          sliderValue: sliderValue,
          sliderMax: sliderMax,
          isPlaying: value.isPlaying,
          fullscreen: false,
          onSeek: onSeek,
          onSeekBy: onSeekBy,
          onTogglePlay: onTogglePlay,
          onFullscreen: onEnterFullscreen,
        ),
      ],
    );
  }
}

class _FullscreenPlayer extends StatelessWidget {
  const _FullscreenPlayer({
    required this.controller,
    required this.title,
    required this.recordingLabel,
    required this.controlsVisible,
    required this.position,
    required this.duration,
    required this.sliderValue,
    required this.sliderMax,
    required this.onTap,
    required this.onShowControls,
    required this.onSeek,
    required this.onSeekBy,
    required this.onTogglePlay,
    required this.onExitFullscreen,
  });

  final VideoPlayerController controller;
  final String title;
  final String recordingLabel;
  final bool controlsVisible;
  final Duration position;
  final Duration duration;
  final double sliderValue;
  final double sliderMax;
  final VoidCallback onTap;
  final VoidCallback onShowControls;
  final ValueChanged<double> onSeek;
  final ValueChanged<Duration> onSeekBy;
  final VoidCallback onTogglePlay;
  final VoidCallback onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final size = value.size;
    final videoWidth = size.width <= 0 ? 16.0 : size.width;
    final videoHeight = size.height <= 0 ? 9.0 : size.height;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: videoWidth,
                  height: videoHeight,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: !controlsVisible,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: onShowControls,
                    child: _PlayerControls(
                      title: title,
                      recordingLabel: recordingLabel,
                      position: position,
                      duration: duration,
                      sliderValue: sliderValue,
                      sliderMax: sliderMax,
                      isPlaying: value.isPlaying,
                      fullscreen: true,
                      onSeek: onSeek,
                      onSeekBy: onSeekBy,
                      onTogglePlay: onTogglePlay,
                      onFullscreen: onExitFullscreen,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.title,
    required this.recordingLabel,
    required this.position,
    required this.duration,
    required this.sliderValue,
    required this.sliderMax,
    required this.isPlaying,
    required this.fullscreen,
    required this.onSeek,
    required this.onSeekBy,
    required this.onTogglePlay,
    required this.onFullscreen,
  });

  final String title;
  final String recordingLabel;
  final Duration position;
  final Duration duration;
  final double sliderValue;
  final double sliderMax;
  final bool isPlaying;
  final bool fullscreen;
  final ValueChanged<double> onSeek;
  final ValueChanged<Duration> onSeekBy;
  final VoidCallback onTogglePlay;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final topPadding = fullscreen ? 18.0 : 8.0;
    return Container(
      decoration: BoxDecoration(
        color: c3Panel.withValues(alpha: fullscreen ? 0.72 : 0.92),
        border: Border(top: BorderSide(color: c3Cyan.withValues(alpha: 0.18))),
      ),
      padding: EdgeInsets.fromLTRB(12, topPadding, 12, 12),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  _formatClock(position),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Expanded(
                  child: Slider(
                    value: sliderValue,
                    max: sliderMax,
                    onChangeStart: (_) {},
                    onChanged: onSeek,
                  ),
                ),
                Text(
                  _formatClock(duration),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  tooltip: 'Back 10 seconds',
                  onPressed: () => onSeekBy(const Duration(seconds: -10)),
                  icon: const Icon(Icons.replay_10),
                ),
                FilledButton(
                  onPressed: onTogglePlay,
                  child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: 'Forward 10 seconds',
                  onPressed: () => onSeekBy(const Duration(seconds: 10)),
                  icon: const Icon(Icons.forward_10),
                ),
                IconButton(
                  tooltip: fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                  onPressed: onFullscreen,
                  icon: Icon(
                    fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                ),
              ],
            ),
            Text(
              fullscreen ? title : recordingLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _toggleWatchLater(BuildContext context, CccEvent event) async {
  final collections = context.read<CollectionService>();
  final wasSaved = collections.isInWatchLater(event.guid);
  await collections.toggleWatchLater(event);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        wasSaved ? 'Removed from Watch Later.' : 'Saved to Watch Later.',
      ),
    ),
  );
}

Future<void> _toggleLiked(BuildContext context, CccEvent event) async {
  final collections = context.read<CollectionService>();
  final wasLiked = collections.isLiked(event.guid);
  await collections.toggleLiked(event);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(wasLiked ? 'Removed from Liked Videos.' : 'Liked video.'),
    ),
  );
}

Future<void> _showCollectionPicker(BuildContext context, CccEvent event) async {
  final rootContext = context;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: c3Panel,
    builder: (sheetContext) {
      return SafeArea(
        child: Consumer<CollectionService>(
          builder: (context, collections, _) {
            final items = collections.collections;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length + 2,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) return const SectionLabel('Add to collection');
                if (index == 1) {
                  return ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('New collection'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(
                        _promptCreateCollection(rootContext, event: event),
                      );
                    },
                  );
                }
                final collection = items[index - 2];
                final saved = collection.contains(event.guid);
                return ListTile(
                  leading: Icon(
                    saved ? Icons.playlist_add_check : Icons.folder_outlined,
                  ),
                  title: Text(collection.title),
                  subtitle: Text('${collection.events.length} videos'),
                  trailing: saved ? const Icon(Icons.check) : null,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await collections.addToCollection(collection.id, event);
                    if (!rootContext.mounted) return;
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      SnackBar(content: Text('Added to ${collection.title}.')),
                    );
                  },
                );
              },
            );
          },
        ),
      );
    },
  );
}

Future<void> _promptCreateCollection(
  BuildContext context, {
  CccEvent? event,
}) async {
  final controller = TextEditingController();
  final title = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('New collection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Collection name'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (!context.mounted || title == null || title.trim().isEmpty) return;
  final collections = context.read<CollectionService>();
  final collection = await collections.createCollection(title);
  if (event != null) {
    await collections.addToCollection(collection.id, event);
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        event == null ? 'Collection created.' : 'Added to ${collection.title}.',
      ),
    ),
  );
}

Future<void> _deleteCollection(
  BuildContext context,
  MediaCollection collection,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Delete collection'),
        content: Text(
          'Delete ${collection.title}? Saved videos stay downloadable elsewhere.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  if (!context.mounted || confirmed != true) return;
  await context.read<CollectionService>().deleteCollection(collection.id);
  if (!context.mounted) return;
  Navigator.of(context).pop();
}

void _openEvent(BuildContext context, CccEvent event) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => EventDetailScreen(initial: event)),
  );
}

void _playRecording(BuildContext context, CccEvent event, Recording recording) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlaybackScreen.online(event: event, recording: recording),
    ),
  );
}

Future<void> _downloadRecording(
  BuildContext context,
  CccEvent event,
  Recording recording,
) async {
  final downloads = context.read<DownloadService>();
  final record = await downloads.queue(event: event, recording: recording);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        record.state == DownloadState.failed
            ? 'Download failed to start.'
            : 'Download started inside c3-UNLOCKED.',
      ),
      action: SnackBarAction(
        label: 'View',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DownloadsRouteScreen()),
        ),
      ),
    ),
  );
}

Future<void> _shareRecording(
  BuildContext context,
  CccEvent event,
  Recording recording,
) async {
  try {
    await _linksChannel.invokeMethod<void>('shareText', <String, String>{
      'title': 'Share video',
      'text': _videoDeepLink(event, recording),
    });
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Share failed: $error')));
  }
}

String _videoDeepLink(CccEvent event, Recording recording) {
  return Uri(
    scheme: 'c3-unlocked',
    host: 'video',
    queryParameters: <String, String>{
      'event': event.guid,
      'url': recording.recordingUrl,
    },
  ).toString();
}

Future<void> _showRecordingPicker(BuildContext context, CccEvent event) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: c3Panel,
    builder: (context) {
      return SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: event.recordings.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final recording = event.recordings[index];
            return ListTile(
              leading: Icon(
                recording.isVideo ? Icons.movie_filter : Icons.audiotrack,
                color: c3Cyan,
              ),
              title: Text(recording.qualityLabel),
              subtitle: Text(
                recording.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Wrap(
                spacing: 4,
                children: <Widget>[
                  if (recording.isVideo)
                    IconButton(
                      tooltip: 'Play',
                      onPressed: () {
                        Navigator.of(context).pop();
                        _playRecording(context, event, recording);
                      },
                      icon: const Icon(Icons.play_arrow),
                    ),
                  IconButton(
                    tooltip: 'Download',
                    onPressed: () {
                      Navigator.of(context).pop();
                      _downloadRecording(context, event, recording);
                    },
                    icon: const Icon(Icons.download),
                  ),
                  IconButton(
                    tooltip: 'Share video',
                    onPressed: () {
                      Navigator.of(context).pop();
                      _shareRecording(context, event, recording);
                    },
                    icon: const Icon(Icons.ios_share),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

Color _stateColor(DownloadState state) {
  switch (state) {
    case DownloadState.completed:
      return c3Lime;
    case DownloadState.failed:
    case DownloadState.missing:
      return const Color(0xFFFF5964);
    case DownloadState.canceled:
      return c3Muted;
    case DownloadState.paused:
      return c3Amber;
    case DownloadState.queued:
    case DownloadState.running:
      return c3Cyan;
  }
}

IconData _stateIcon(DownloadState state) {
  switch (state) {
    case DownloadState.completed:
      return Icons.check_circle;
    case DownloadState.failed:
    case DownloadState.missing:
      return Icons.error_outline;
    case DownloadState.canceled:
      return Icons.cancel_outlined;
    case DownloadState.paused:
      return Icons.pause_circle_outline;
    case DownloadState.queued:
      return Icons.schedule;
    case DownloadState.running:
      return Icons.downloading;
  }
}

String? _videoDeepLinkEventId(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'c3-unlocked' || uri.host != 'video') {
    return null;
  }
  final id = uri.queryParameters['event']?.trim();
  return id == null || id.isEmpty ? null : id;
}

({CccEvent event, Recording recording})? _directRecordingFromLink(String raw) {
  final url = _directRecordingUrl(raw);
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final filename = uri.pathSegments.isEmpty
      ? 'recording'
      : Uri.decodeComponent(uri.pathSegments.last);
  final recording = Recording(
    id: stableId(url),
    recordingUrl: url,
    filename: filename,
    mimeType: _mimeTypeForUrl(url),
  );
  final event = CccEvent(
    guid: stableId('direct:$url'),
    title: filename,
    frontendLink: url,
    recordings: <Recording>[recording],
  );
  return (event: event, recording: recording);
}

String? _directRecordingUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  if (uri.scheme == 'c3-unlocked' && uri.host == 'video') {
    final embedded = uri.queryParameters['url'];
    if (embedded == null || embedded.trim().isEmpty) return null;
    return embedded;
  }
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final isMediaHost =
      host == 'cdn.media.ccc.de' || host == 'static.media.ccc.de';
  final isRecording =
      path.endsWith('.mp4') ||
      path.endsWith('.m4v') ||
      path.endsWith('.webm') ||
      path.endsWith('.mp3') ||
      path.endsWith('.opus');
  return isMediaHost && isRecording ? uri.toString() : null;
}

bool _looksLikeLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return false;
  return uri.scheme == 'https' ||
      uri.scheme == 'http' ||
      uri.scheme == 'c3-unlocked';
}

String _mimeTypeForUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (path.endsWith('.mp4') || path.endsWith('.m4v')) return 'video/mp4';
  if (path.endsWith('.webm')) return 'video/webm';
  if (path.endsWith('.mp3')) return 'audio/mpeg';
  if (path.endsWith('.opus')) return 'audio/opus';
  return 'application/octet-stream';
}

String _formatClock(Duration value) {
  final total = value.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
