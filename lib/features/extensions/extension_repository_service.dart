import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'extension_models.dart';
import 'protobuf_index_decoder.dart';

class ExtensionRepositoryService {
  static const String defaultRepositoryUrl =
      'https://raw.githubusercontent.com/yuzono/manga-repo/repo/index.min.json';
  static const String _storageKey = 'extension_repositories_v1';
  final http.Client _client;

  ExtensionRepositoryService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<ExtensionRepository>> loadRepositories() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_storageKey) ?? <String>[];
    final repositories = <ExtensionRepository>[];
    for (final value in stored) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          repositories.add(ExtensionRepository.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } on FormatException {
        // Ignore malformed stored entries.
      } on TypeError {
        // Ignore malformed stored entries.
      }
    }
    if (repositories.isEmpty) {
      final defaults = <ExtensionRepository>[const ExtensionRepository(url: defaultRepositoryUrl, name: 'Yuzono')];
      await saveRepositories(defaults);
      return defaults;
    }
    if (!repositories.any((r) => r.url == defaultRepositoryUrl)) {
      repositories.add(const ExtensionRepository(url: defaultRepositoryUrl, name: 'Yuzono'));
      await saveRepositories(repositories);
    }
    return repositories;
  }

  Future<void> saveRepositories(List<ExtensionRepository> repositories) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      repositories.map((r) => jsonEncode(r.toJson())).toList(growable: false),
    );
  }

  Future<List<ExtensionEntry>> fetchExtensions(List<ExtensionRepository> repositories) async {
    final entriesByPackage = <String, ExtensionEntry>{};
    final failures = <String>[];
    for (final repository in repositories) {
      try {
        final entries = await _fetchRepository(repository);
        for (final entry in entries) {
          if (entry.packageName.isEmpty) continue;
          final existing = entriesByPackage[entry.packageName];
          if (existing == null || entry.versionCode > existing.versionCode) {
            entriesByPackage[entry.packageName] = entry;
          }
        }
      } catch (error) {
        failures.add('${repository.name}: ${error.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (entriesByPackage.isEmpty && failures.isNotEmpty) {
      throw Exception(failures.join('\n'));
    }
    final result = entriesByPackage.values.toList(growable: true)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<List<ExtensionEntry>> _fetchRepository(ExtensionRepository repository) async {
    final uri = Uri.tryParse(repository.url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      throw FormatException('Invalid repository URL: ${repository.url}');
    }

    final path = uri.path.toLowerCase();
    if (path.endsWith('.pb')) {
      final bytes = await _getBytes(uri);
      return _mapProtobuf(bytes, repository.url);
    }
    if (path.endsWith('repo.json')) {
      return _fetchRepoJson(uri, repository.url);
    }

    // First attempt the legacy JSON index. If this is a repository root or a
    // newer store URL, follow repo.json/index.pb as a compatibility fallback.
    try {
      final bytes = await _getBytes(uri);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is List) return _mapLegacyJson(decoded, repository.url);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        if (map['index_v2'] != null) {
          final indexUri = uri.resolve(map['index_v2'].toString());
          return _mapProtobuf(await _getBytes(indexUri), repository.url);
        }
        if (map['meta'] is Map) {
          final repoJsonUri = uri.resolve('repo.json');
          return _fetchRepoJson(repoJsonUri, repository.url);
        }
      }
      throw const FormatException('Unrecognized repository index format.');
    } catch (legacyError) {
      final repoJsonUri = _repoJsonUri(uri);
      try {
        return await _fetchRepoJson(repoJsonUri, repository.url);
      } catch (_) {
        final pbUri = _indexPbUri(uri);
        try {
          return _mapProtobuf(await _getBytes(pbUri), repository.url);
        } catch (pbError) {
          throw Exception('Could not read JSON or protobuf index. $legacyError; $pbError');
        }
      }
    }
  }

  Future<List<ExtensionEntry>> _fetchRepoJson(Uri uri, String originalUrl) async {
    final bytes = await _getBytes(uri);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('repo.json must contain a JSON object.');
    final map = Map<String, dynamic>.from(decoded);
    final indexPath = map['index_v2']?.toString();
    if (indexPath == null || indexPath.isEmpty) {
      // Some compatible repositories publish repo.json metadata but keep the
      // protobuf index at the conventional sibling path.
      final fallback = _indexPbUri(uri);
      return _mapProtobuf(await _getBytes(fallback), originalUrl);
    }
    return _mapProtobuf(await _getBytes(uri.resolve(indexPath)), originalUrl);
  }

  Future<Uint8List> _getBytes(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: const <String, String>{'Accept': 'application/json, application/octet-stream'},
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode} at $uri');
    return response.bodyBytes;
  }

  List<ExtensionEntry> _mapLegacyJson(List<dynamic> decoded, String repositoryUrl) {
    final result = <ExtensionEntry>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final entry = ExtensionEntry.fromJson(Map<String, dynamic>.from(item), repositoryUrl: repositoryUrl);
      if (entry.packageName.isNotEmpty && entry.apkFile.isNotEmpty) result.add(entry);
    }
    return result;
  }

  List<ExtensionEntry> _mapProtobuf(Uint8List bytes, String repositoryUrl) {
    final decoded = ProtobufIndexDecoder.decodeExtensions(bytes);
    return decoded.map((item) => ExtensionEntry.fromJson(item, repositoryUrl: repositoryUrl))
        .where((entry) => entry.packageName.isNotEmpty && entry.apkUrl.isNotEmpty)
        .toList(growable: false);
  }

  Uri _repositoryDirectory(Uri uri) {
    return uri.path.endsWith('/') ? uri : uri.resolve('.');
  }

  Uri _repoJsonUri(Uri uri) => _repositoryDirectory(uri).resolve('repo.json');

  Uri _indexPbUri(Uri uri) => _repositoryDirectory(uri).resolve('index.pb');
}
