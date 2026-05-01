import 'package:flutter/material.dart';

import '../models/app_location.dart';
import '../models/news_article.dart';
import '../services/article_content_service.dart';
import '../services/location_service.dart';
import '../services/news_service.dart';
import '../storage/haven_cache.dart';
import '../ui/glass_theme.dart';

class NewspaperScreen extends StatefulWidget {
  const NewspaperScreen({super.key});

  @override
  State<NewspaperScreen> createState() => _NewspaperScreenState();
}

class _NewspaperScreenState extends State<NewspaperScreen> {
  List<NewsArticle> _articles = [];
  DateTime? _lastRefresh;
  AppLocation? _location;
  bool _refreshing = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _articles = HavenCache.getNews();
    _lastRefresh = HavenCache.getLastRefresh();
    _location = HavenCache.getLastLocation() ?? LocationService.defaultLocation;
    if (_articles.isEmpty) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _status = null;
      _error = null;
    });

    try {
      final location = await LocationService().getCurrentLocation();
      final articles = await NewsService().fetchLocalNews(location!);
      final refreshedAt = DateTime.now();
      if (!mounted) return;
      setState(() {
        _articles = articles;
        _location = location;
        _lastRefresh = refreshedAt;
        _status = 'Fetched ${articles.length} reports for ${location.label}.';
        if (articles.isEmpty) {
          _error =
              'Fetch completed but returned 0 reports. Try again or check network restrictions.';
        }
      });
      await HavenCache.saveNews(articles);
      await HavenCache.markRefreshed();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not refresh. Showing cached newspaper.';
        _status = _articles.isEmpty
            ? 'No reports loaded yet.'
            : 'Showing ${_articles.length} cached reports.';
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final articles = _articles;
    final location = _location;
    final lastRefresh = _lastRefresh;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          GlassPanel(
            opacity: 0.2,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Offline Newspaper',
                        style: TextStyle(
                          color: GlassColors.textPrimary,
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          GlassPill(
                            label: location?.label ?? 'unknown area',
                            icon: Icons.location_on_outlined,
                            color: GlassColors.cyan,
                          ),
                          GlassPill(
                            label: _formatDate(lastRefresh),
                            icon: Icons.schedule_outlined,
                            color: GlassColors.safe,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _refreshing
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : GlassIconButton(
                        onPressed: _refresh,
                        icon: Icons.refresh,
                        color: GlassColors.textPrimary,
                      ),
              ],
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _status!,
                style: const TextStyle(color: GlassColors.safe, fontSize: 12),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: GlassColors.amber, fontSize: 12),
              ),
            ),
          const GlassSectionHeader(
            title: 'Local Reports',
            subtitle: 'Cached for offline reading when connectivity drops',
          ),
          if (articles.isEmpty)
            GlassPanel(
              borderRadius: 22,
              opacity: 0.12,
              child: Text(
                _emptyMessage,
                style: const TextStyle(color: GlassColors.textSecondary),
              ),
            )
          else
            ...articles.map(
              (article) =>
                  _ArticleCard(article, onArticleUpdated: _updateArticle),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'never';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  String get _emptyMessage {
    if (_refreshing) {
      return 'Fetching Tehran reports now...';
    }
    if (_error != null) {
      return _error!;
    }
    return 'No reports loaded yet. Tap refresh to fetch Tehran news from Google News RSS, GDELT, and GDACS.';
  }

  void _updateArticle(NewsArticle article) {
    setState(() {
      _articles = [
        for (final existing in _articles)
          if (existing.id == article.id) article else existing,
      ];
    });
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard(this.article, {required this.onArticleUpdated});

  final NewsArticle article;
  final ValueChanged<NewsArticle> onArticleUpdated;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showArticleDetails(
        context,
        article,
        onArticleUpdated: onArticleUpdated,
      ),
      child: GlassPanel(
        borderRadius: 24,
        opacity: 0.14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              article.title,
              style: const TextStyle(
                color: GlassColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.18,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GlassPill(
                  label: article.source,
                  icon: Icons.public_outlined,
                  color: GlassColors.cyan,
                ),
                GlassPill(
                  label: _dateOnly(article.publishedAt),
                  icon: Icons.calendar_today_outlined,
                  color: GlassColors.safe,
                ),
              ],
            ),
            if (article.summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                article.summary,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GlassColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _dateOnly(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

void _showArticleDetails(
  BuildContext context,
  NewsArticle article, {
  required ValueChanged<NewsArticle> onArticleUpdated,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return _ArticleReaderSheet(
            initialArticle: article,
            scrollController: scrollController,
            onArticleUpdated: onArticleUpdated,
          );
        },
      );
    },
  );
}

class _ArticleReaderSheet extends StatefulWidget {
  const _ArticleReaderSheet({
    required this.initialArticle,
    required this.scrollController,
    required this.onArticleUpdated,
  });

  final NewsArticle initialArticle;
  final ScrollController scrollController;
  final ValueChanged<NewsArticle> onArticleUpdated;

  @override
  State<_ArticleReaderSheet> createState() => _ArticleReaderSheetState();
}

class _ArticleReaderSheetState extends State<_ArticleReaderSheet> {
  late NewsArticle _article;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _article = widget.initialArticle;
    if ((_article.content ?? '').trim().length < 300) {
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    setState(() => _loading = true);
    final updated = await ArticleContentService().fetchFullContent(_article);
    await HavenCache.saveNewsArticle(updated);
    if (!mounted) return;
    setState(() {
      _article = updated;
      _loading = false;
    });
    widget.onArticleUpdated(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: GlassPanel(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        borderRadius: 34,
        opacity: 0.22,
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              _article.title,
              style: const TextStyle(
                color: GlassColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                height: 1.14,
                letterSpacing: -0.7,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GlassPill(
                  label: _article.source,
                  icon: Icons.public_outlined,
                  color: GlassColors.cyan,
                ),
                GlassPill(
                  label: _fullDate(_article.publishedAt),
                  icon: Icons.calendar_today_outlined,
                  color: GlassColors.safe,
                ),
                if (_article.locationLabel != null)
                  GlassPill(
                    label: _article.locationLabel!,
                    icon: Icons.location_on_outlined,
                    color: GlassColors.amber,
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Full Article Text',
                    style: TextStyle(
                      color: GlassColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_article.contentStatus != null) ...[
              const SizedBox(height: 8),
              Text(
                _article.contentStatus!,
                style: const TextStyle(color: GlassColors.amber, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              (_article.content ?? '').trim().isNotEmpty
                  ? _article.content!
                  : _article.summary.isEmpty
                  ? 'No article text was available yet. The source may block extraction; use the source URL below for the original report.'
                  : _article.summary,
              style: const TextStyle(
                color: GlassColors.textSecondary,
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Source URL',
              style: TextStyle(
                color: GlassColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _article.url,
              style: const TextStyle(
                color: GlassColors.cyan,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Fetched at ${_fullDateTime(_article.fetchedAt)}'
              '${_article.contentFetchedAt == null ? '' : ' • content ${_fullDateTime(_article.contentFetchedAt!)}'}',
              style: const TextStyle(
                color: GlassColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fullDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _fullDateTime(DateTime value) =>
    '${_fullDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
