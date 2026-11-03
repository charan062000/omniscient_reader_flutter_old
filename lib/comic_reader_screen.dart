import 'dart:typed_data';
import 'package:flutter/material.dart';

class ComicReaderScreen extends StatefulWidget {
  final String title;
  final List<Uint8List> pages;

  const ComicReaderScreen({
    super.key,
    required this.title,
    required this.pages,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  // Toggle between Webtoon (vertical) and Standard (horizontal page-by-page)
  bool isWebtoonMode = true;
  final PageController _pageController = PageController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Switch Mode',
            icon: Icon(
              isWebtoonMode ? Icons.view_day : Icons.view_carousel,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                isWebtoonMode = !isWebtoonMode;
              });
            },
          ),
        ],
      ),
      body: widget.pages.isEmpty
          ? const Center(
              child: Text(
                'No images found in this comic.',
                style: TextStyle(color: Colors.white),
              ),
            )
          : isWebtoonMode
              ? _buildWebtoonView()
              : _buildPagedView(),
    );
  }

  // 1. Webtoon Mode: Continuous vertical scroll
  Widget _buildWebtoonView() {
    return ListView.builder(
      itemCount: widget.pages.length,
      itemBuilder: (context, index) {
        return Image.memory(
          widget.pages[index],
          fit: BoxFit.fitWidth,
          // Prevents jitter while loading
          gaplessPlayback: true,
        );
      },
    );
  }

  // 2. Standard Mode: Horizontal swipe (Left-to-Right)
  Widget _buildPagedView() {
    return PageView.builder(
      controller: _pageController,
      itemCount: widget.pages.length,
      itemBuilder: (context, index) {
        return Center(
          child: InteractiveViewer(
            // Allows pinch-to-zoom
            minScale: 1.0,
            maxScale: 4.0,
            child: Image.memory(
              widget.pages[index],
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}
