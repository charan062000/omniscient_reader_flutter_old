import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:permission_handler/permission_handler.dart';
import 'comic_reader_screen.dart';

void main() {
  runApp(const OmniscientReaderApp());
}

class OmniscientReaderApp extends StatelessWidget {
  const OmniscientReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omniscient Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
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
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const LibraryScreen(),
    const ComicBrowserScreen(),
    const NovelBrowserScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Comics/CBZ',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'EPUB/Novels',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// 1. Library Screen with File Picker & CBZ Unpacker
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _isLoading = false;

  // Function to pick and unpack CBZ/ZIP files
  Future<void> _pickAndOpenComic(BuildContext context) async {
    // Request storage permissions
    await Permission.storage.request();

    // Pick file
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cbz', 'zip'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _isLoading = true;
      });

      File file = File(result.files.single.path!);
      String comicTitle = result.files.single.name;

      try {
        // Read zip/cbz bytes
        List<int> bytes = await file.readAsBytes();
        Archive archive = ZipDecoder().decodeBytes(bytes);

        List<Uint8List> imagePages = [];

        // Filter and sort image entries
        List<ArchiveFile> imageFiles = archive.files.where((entry) {
          final name = entry.name.toLowerCase();
          return entry.isFile &&
              (name.endsWith('.jpg') ||
                  name.endsWith('.jpeg') ||
                  name.endsWith('.png') ||
                  name.endsWith('.webp'));
        }).toList();

        // Sort pages alphabetically (01.jpg, 02.jpg...)
        imageFiles.sort((a, b) => a.name.compareTo(b.name));

        for (var entry in imageFiles) {
          imagePages.add(Uint8List.fromList(entry.content as List<int>));
        }

        setState(() {
          _isLoading = false;
        });

        // Open Reader
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ComicReaderScreen(
                title: comicTitle,
                pages: imagePages,
              ),
            ),
          );
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to read CBZ: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Library')),
      body: Center(
        child: _isLoading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Extracting comic pages...'),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_stories, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Open and read local files'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _pickAndOpenComic(context),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Pick CBZ / ZIP Comic'),
                  ),
                ],
              ),
      ),
    );
  }
}

class ComicBrowserScreen extends StatelessWidget {
  const ComicBrowserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comics & Manhwa')),
      body: const Center(child: Text('Online Sources Module (Coming Next)')),
    );
  }
}

class NovelBrowserScreen extends StatelessWidget {
  const NovelBrowserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EPUB & Novels')),
      body: const Center(child: Text('Novel & Injected Images Module')),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings')),
    );
  }
}
