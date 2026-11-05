import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'extension_models.dart';
import 'extension_repository_service.dart';

class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final ExtensionRepositoryService _repositoryService =
      ExtensionRepositoryService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<ExtensionRepository> _repositories = <ExtensionRepository>[];
  List<ExtensionEntry> _extensions = <ExtensionEntry>[];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _languageFilter = 'All';
  bool _showNsfw = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _searchController.addListener(_onSearchChanged);
    _initialize();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameController.dispose();
    _urlController.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final repositories = await _repositoryService.loadRepositories();
      if (!mounted) return;
      setState(() {
        _repositories = repositories;
        _loading = false;
      });
      await _refreshExtensions();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _refreshExtensions() async {
    if (_repositories.isEmpty) {
      if (!mounted) return;
      setState(() {
        _extensions = <ExtensionEntry>[];
        _error = null;
        _refreshing = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }

    try {
      final fetched =
          await _repositoryService.fetchExtensions(_repositories);
      if (!mounted) return;
      setState(() {
        _extensions = fetched;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _addRepository() async {
    _nameController.clear();
    _urlController.clear();
    String? validationError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add extension repository'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Repository name',
                      hintText: 'My repository',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Repository index URL',
                      hintText: 'https://example.org/index.min.json',
                      errorText: validationError,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Supports legacy index.min.json and modern repo.json / index.pb repositories.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final rawUrl = _urlController.text.trim();
                    final parsedUri = Uri.tryParse(rawUrl);

                    if (parsedUri == null ||
                        (parsedUri.scheme != 'https' &&
                            parsedUri.scheme != 'http') ||
                        parsedUri.host.isEmpty ||
                        !(parsedUri.path.toLowerCase().endsWith('.json') ||
                            parsedUri.path.toLowerCase().endsWith('.pb') ||
                            parsedUri.path.endsWith('/'))) {
                      setDialogState(() {
                        validationError =
                            'Enter a valid HTTP(S) repo.json, index.json, index.pb or repository URL';
                      });
                      return;
                    }

                    final canonicalUrl = parsedUri.toString();
                    final alreadyAdded = _repositories.any(
                      (repository) =>
                          repository.url.toLowerCase() ==
                          canonicalUrl.toLowerCase(),
                    );
                    if (alreadyAdded) {
                      setDialogState(() {
                        validationError = 'Repository already exists';
                      });
                      return;
                    }

                    final repositoryName = _nameController.text.trim().isEmpty
                        ? parsedUri.host
                        : _nameController.text.trim();

                    final newRepository = ExtensionRepository(
                      name: repositoryName,
                      url: canonicalUrl,
                    );

                    try {
                      await _repositoryService
                          .fetchExtensions(<ExtensionRepository>[
                        newRepository,
                      ]);
                    } catch (error) {
                      if (!context.mounted) return;
                      setDialogState(() {
                        validationError =
                            'Repository check failed: ${error.toString()}';
                      });
                      return;
                    }

                    if (!mounted || !dialogContext.mounted) return;
                    final updated = <ExtensionRepository>[
                      ..._repositories,
                      newRepository,
                    ];
                    setState(() => _repositories = updated);
                    await _repositoryService.saveRepositories(updated);
                    if (!mounted || !dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    await _refreshExtensions();
                  },
                  child: const Text('Add repository'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _removeRepository(
    ExtensionRepository repository,
  ) async {
    final updated = _repositories
        .where((item) => item.url != repository.url)
        .toList(growable: false);
    setState(() => _repositories = updated);
    await _repositoryService.saveRepositories(updated);
    await _refreshExtensions();
  }

  List<String> get _languages {
    final languages =
        _extensions.map((entry) => entry.language).toSet().toList()..sort();
    return <String>['All', ...languages];
  }

  List<ExtensionEntry> get _filteredExtensions {
    final query = _searchController.text.trim().toLowerCase();
    return _extensions.where((extension) {
      if (!_showNsfw && extension.isNsfw) return false;
      if (_languageFilter != 'All' &&
          extension.language.toLowerCase() !=
              _languageFilter.toLowerCase()) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchesExtension =
            extension.name.toLowerCase().contains(query);
        final matchesSource = extension.sources.any(
          (source) => source.name.toLowerCase().contains(query),
        );
        if (!matchesExtension && !matchesSource) return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<void> _openApk(ExtensionEntry extension) async {
    final uri = Uri.tryParse(extension.apkUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _showMessage('Invalid APK download URL');
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) _showMessage('Could not open the APK download link');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Extensions',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh repositories',
            onPressed: _refreshing ? null : _refreshExtensions,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Add repository',
            onPressed: _addRepository,
            icon: const Icon(Icons.add_link_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Extensions (${_extensions.length})'),
            Tab(text: 'Repositories (${_repositories.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildExtensionsTab(),
          _buildRepositoriesTab(),
        ],
      ),
    );
  }

  Widget _buildExtensionsTab() {
    if (_loading || _refreshing && _extensions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _extensions.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load extension catalogue',
        message: _error!,
        actionLabel: 'Try again',
        onAction: _refreshExtensions,
      );
    }

    final entries = _filteredExtensions;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search extensions or sources',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: [
              for (final language in _languages)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(language.toUpperCase()),
                    selected: _languageFilter == language,
                    onSelected: (_) {
                      setState(() => _languageFilter = language);
                    },
                  ),
                ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          title: const Text('Show adult-content extensions'),
          value: _showNsfw,
          onChanged: (value) => setState(() => _showNsfw = value),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.orange, fontSize: 11),
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? const _MessageState(
                  icon: Icons.extension_off_outlined,
                  title: 'No extensions found',
                  message:
                      'Refresh the repository or change your search and language filters.',
                )
              : RefreshIndicator(
                  onRefresh: _refreshExtensions,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final extension = entries[index];
                      return _ExtensionCard(
                        extension: extension,
                        onDownload: () => _openApk(extension),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRepositoriesTab() {
    if (_repositories.isEmpty) {
      return _MessageState(
        icon: Icons.dns_outlined,
        title: 'No repositories',
        message:
            'Add a Mihon-compatible JSON or protobuf repository to browse extensions.',
        actionLabel: 'Add repository',
        onAction: _addRepository,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _repositories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final repository = _repositories[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.dns_rounded),
            ),
            title: Text(repository.name),
            subtitle: Text(
              repository.url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Remove repository',
              onPressed: () => _removeRepository(repository),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        );
      },
    );
  }
}

class _ExtensionCard extends StatelessWidget {
  final ExtensionEntry extension;
  final VoidCallback onDownload;

  const _ExtensionCard({
    required this.extension,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.extension_rounded,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    extension.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${extension.displayLanguage} · v${extension.version}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (extension.sources.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      extension.sources.map((source) => source.name).join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onDownload,
              child: const Text('Download APK'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
