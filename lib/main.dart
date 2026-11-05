import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'comic_reader_screen.dart';
import 'features/extensions/extensions_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OmniscientReaderApp());
}

class AppColors {
  static const background = Color(0xFF0B0D12);
  static const surface = Color(0xFF131722);
  static const surfaceRaised = Color(0xFF1A2030);
  static const line = Color(0xFF252C3B);
  static const muted = Color(0xFF929BAD);
  static const accent = Color(0xFFB69CFF);
  static const accentBright = Color(0xFFD0BEFF);
}

class OmniscientReaderApp extends StatelessWidget {
  const OmniscientReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      surface: AppColors.surface,
    );

    return MaterialApp(
      title: 'Omniscient Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF10141D),
          indicatorColor: AppColors.accent.withValues(alpha: 0.16),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.accentBright : AppColors.muted,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? AppColors.accentBright : AppColors.muted,
              size: 22,
            );
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          hintStyle: const TextStyle(color: AppColors.muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.3),
          ),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    LibraryScreen(),
    BrowseScreen(),
    UpdatesScreen(),
    DownloadsScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _selectedIndex, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_mosaic_outlined),
            selectedIcon: Icon(Icons.auto_awesome_mosaic_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none_rounded),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'Updates',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_for_offline_outlined),
            selectedIcon: Icon(Icons.download_for_offline_rounded),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _isImporting = false;
  final List<LibraryEntry> _library = [];

  Future<void> _pickComic() async {
    if (_isImporting) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['cbz', 'zip'],
        withData: true,
      );

      if (!mounted || result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null) {
        _showMessage('Could not read this file. Please select it again.');
        return;
      }

      setState(() => _isImporting = true);

      // Decode in-memory bytes. This works for Android and the Chrome preview;
      // no dart:io File access or broad storage permission is required.
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final imageEntries = archive.files.where((entry) {
        final name = entry.name.toLowerCase();
        return entry.isFile &&
            (name.endsWith('.jpg') ||
                name.endsWith('.jpeg') ||
                name.endsWith('.png') ||
                name.endsWith('.webp') ||
                name.endsWith('.gif'));
      }).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (imageEntries.isEmpty) {
        if (mounted) {
          setState(() => _isImporting = false);
          _showMessage('No supported comic images were found in this archive.');
        }
        return;
      }

      final pages = <Uint8List>[];
      for (final entry in imageEntries) {
        pages.add(Uint8List.fromList(entry.content as List<int>));
      }

      if (!mounted) return;
      setState(() {
        _library.insert(
          0,
          LibraryEntry(
            title: picked.name.replaceFirst(
                RegExp(r'\.(cbz|zip)$', caseSensitive: false), ''),
            pageCount: pages.length,
            pages: pages,
          ),
        );
        _isImporting = false;
      });

      _showMessage('${picked.name} added to your library');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      _showMessage(
          'Unable to open this archive. Check that the ZIP/CBZ is valid.');
      debugPrint('Comic import error: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceRaised,
        ),
      );
  }

  void _openComic(LibraryEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComicReaderScreen(
          title: entry.title,
          pages: entry.pages,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB69CFF), Color(0xFF7658C9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.auto_stories_rounded,
                      color: Color(0xFF171126), size: 23),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OMNISCIENT',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accentBright,
                          )),
                      SizedBox(height: 2),
                      Text('Your reading universe',
                          style:
                              TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Search library',
                  onPressed: () =>
                      _showMessage('Library search is coming next.'),
                  icon: const Icon(Icons.search_rounded),
                ),
                IconButton(
                  tooltip: 'Import comic',
                  onPressed: _isImporting ? null : _pickComic,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
          sliver: SliverToBoxAdapter(
            child: _LibraryHero(
              isImporting: _isImporting,
              onImport: _pickComic,
              itemCount: _library.length,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                const Expanded(
                  child: Text('My library',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                ),
                _CountPill(count: _library.length),
                const SizedBox(width: 8),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      _showMessage('Library filters are coming next.'),
                  icon: const Icon(Icons.tune_rounded, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
        if (_library.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
            sliver: SliverToBoxAdapter(
              child: _EmptyLibraryCard(onImport: _pickComic),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = _library[index];
                  return _LibraryTile(
                    entry: entry,
                    onTap: () => _openComic(entry),
                  );
                },
                childCount: _library.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 13,
                mainAxisSpacing: 15,
                childAspectRatio: 0.76,
              ),
            ),
          ),
      ],
    );
  }
}

class LibraryEntry {
  final String title;
  final int pageCount;
  final List<Uint8List> pages;

  const LibraryEntry({
    required this.title,
    required this.pageCount,
    required this.pages,
  });
}

class _LibraryHero extends StatelessWidget {
  final bool isImporting;
  final int itemCount;
  final VoidCallback onImport;

  const _LibraryHero({
    required this.isImporting,
    required this.itemCount,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: const LinearGradient(
          colors: [Color(0xFF29213F), Color(0xFF171B2A), Color(0xFF131722)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -5,
            top: 4,
            child: Icon(Icons.auto_stories_rounded,
                size: 105, color: Colors.white.withValues(alpha: 0.055)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Eyebrow(text: 'WELCOME BACK'),
              const SizedBox(height: 12),
              const Text(
                'Every story,\\none universe.',
                style: TextStyle(
                    fontSize: 27,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7),
              ),
              const SizedBox(height: 9),
              Text(
                itemCount == 0
                    ? 'Build your personal library and pick up where you left off.'
                    : '$itemCount ${itemCount == 1 ? 'title' : 'titles'} in your library. Your next chapter awaits.',
                style: const TextStyle(
                    color: Color(0xFFB4B8C7), height: 1.45, fontSize: 12.5),
              ),
              const SizedBox(height: 19),
              FilledButton.icon(
                onPressed: isImporting ? null : onImport,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentBright,
                  foregroundColor: const Color(0xFF201735),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: isImporting
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_open_rounded, size: 18),
                label: Text(isImporting ? 'Importing…' : 'Import a comic'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyLibraryCard extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyLibraryCard({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 25),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(21),
            ),
            child: const Icon(Icons.collections_bookmark_outlined,
                color: AppColors.accentBright, size: 31),
          ),
          const SizedBox(height: 17),
          const Text('Your library is waiting',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          const Text(
            'Import a CBZ or ZIP comic to start reading. Online sources and extension support will be added in the next stages.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 12),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: onImport,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentBright,
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.55)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
            ),
            child: const Text('Choose a file'),
          ),
        ],
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  final LibraryEntry entry;
  final VoidCallback onTap;

  const _LibraryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final preview = entry.pages.isNotEmpty ? entry.pages.first : null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (preview != null)
                    Image.memory(preview, fit: BoxFit.cover)
                  else
                    const ColoredBox(
                      color: AppColors.surfaceRaised,
                      child: Icon(Icons.menu_book_rounded,
                          size: 42, color: AppColors.muted),
                    ),
                  const Positioned(
                    left: 9,
                    top: 9,
                    child: const _Tag(text: 'CBZ / ZIP'),
                  ),
                  Positioned(
                    right: 9,
                    bottom: 9,
                    child: _Tag(text: '${entry.pageCount} pages'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
              child: Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, height: 1.25),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _SimplePage(
      eyebrow: 'DISCOVER',
      title: 'Find your next\\nobsession.',
      subtitle:
          'Explore manga, manhwa, manhua and novels through configurable sources.',
      icon: Icons.explore_rounded,
      child: Column(
        children: [
          TextField(
            readOnly: true,
            onTap: () => _showComingSoon(context, 'Source search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search titles, authors or genres',
              suffixIcon: Icon(Icons.tune_rounded),
            ),
          ),
          const SizedBox(height: 18),
          _FeatureRow(
            icon: Icons.extension_rounded,
            title: 'Extensions & sources',
            subtitle: 'Manage repositories and supported catalogue sources',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ExtensionsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _FeatureRow(
            icon: Icons.local_fire_department_outlined,
            title: 'Popular and latest',
            subtitle: 'Discover titles from your installed sources',
          ),
          const SizedBox(height: 10),
          const _FeatureRow(
            icon: Icons.category_outlined,
            title: 'Genres and filters',
            subtitle: 'Narrow down your next read',
          ),
          const SizedBox(height: 18),
          const _ComingSoonNote(),
        ],
      ),
    );
  }
}

class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SimplePage(
      eyebrow: 'YOUR FOLLOWING LIST',
      title: 'Latest\\nupdates.',
      subtitle: 'New chapters from titles in your library will appear here.',
      icon: Icons.notifications_active_outlined,
      child: const _EmptyState(
        icon: Icons.rss_feed_rounded,
        title: 'No chapter updates yet',
        subtitle:
            'Add titles and connect a source. New chapter notifications and update history will live here.',
      ),
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SimplePage(
      eyebrow: 'READ OFFLINE',
      title: 'Your downloads.',
      subtitle: 'Keep chapters ready for reading, even without a connection.',
      icon: Icons.download_rounded,
      child: const _EmptyState(
        icon: Icons.cloud_download_outlined,
        title: 'Nothing downloading',
        subtitle:
            'Your active queue, completed chapters and offline storage will appear here.',
      ),
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _SimplePage(
      eyebrow: 'PERSONALISE',
      title: 'Your reading\\nspace.',
      subtitle: 'Manage the app and shape the way you read.',
      icon: Icons.tune_rounded,
      child: Column(
        children: [
          _MenuTile(
            icon: Icons.extension_rounded,
            title: 'Extensions',
            subtitle: 'Installed sources and repositories',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ExtensionsScreen(),
              ),
            ),
          ),
          _MenuTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Theme, colour and layout preferences',
            onTap: () => _showComingSoon(context, 'Appearance settings'),
          ),
          _MenuTile(
            icon: Icons.chrome_reader_mode_outlined,
            title: 'Reader settings',
            subtitle: 'Reading direction, gestures and display',
            onTap: () => _showComingSoon(context, 'Reader settings'),
          ),
          _MenuTile(
            icon: Icons.backup_outlined,
            title: 'Backup & restore',
            subtitle: 'Protect your library and preferences',
            onTap: () => _showComingSoon(context, 'Backup and restore'),
          ),
          _MenuTile(
            icon: Icons.info_outline_rounded,
            title: 'About Omniscient Reader',
            subtitle: 'Version 1.0.0 · Early development',
            onTap: () => _showComingSoon(context, 'About'),
          ),
        ],
      ),
    );
  }
}

class _SimplePage extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _SimplePage({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 27, 22, 28),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _Eyebrow(text: 'OMNISCIENT READER'),
                    const Spacer(),
                    Icon(icon, color: AppColors.accentBright, size: 23),
                  ],
                ),
                const SizedBox(height: 22),
                Text(title,
                    style: const TextStyle(
                        fontSize: 34,
                        height: 1.05,
                        letterSpacing: -1.1,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.muted, height: 1.5, fontSize: 13)),
                const SizedBox(height: 25),
                child,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              _IconTile(icon: icon),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                            height: 1.35)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(17),
        child: ListTile(
          onTap: onTap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          leading: _IconTile(icon: icon),
          title: Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: Text(subtitle,
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          trailing:
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;

  const _IconTile({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 43,
      height: 43,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: AppColors.accentBright, size: 21),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: AppColors.accentBright),
          const SizedBox(height: 13),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.muted, fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }
}

class _ComingSoonNote extends StatelessWidget {
  const _ComingSoonNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.17)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: AppColors.accentBright, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Online catalogues are not connected yet. The source and extension system will be implemented as a separate module.',
              style: TextStyle(
                  color: Color(0xFFC4BED7), fontSize: 11, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;

  const _Eyebrow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.accentBright,
        fontSize: 10,
        letterSpacing: 1.8,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;

  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xCC090B10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;

  const _CountPill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$count',
          style: const TextStyle(
              color: AppColors.accentBright,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}

void _showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content:
            Text('$feature will be implemented in the next development stage.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceRaised,
      ),
    );
}
