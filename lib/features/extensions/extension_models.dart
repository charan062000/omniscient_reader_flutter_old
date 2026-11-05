class ExtensionRepository {
  final String url;
  final String name;

  const ExtensionRepository({required this.url, required this.name});

  Map<String, dynamic> toJson() => <String, dynamic>{'url': url, 'name': name};

  factory ExtensionRepository.fromJson(Map<String, dynamic> json) {
    return ExtensionRepository(
      url: json['url'] as String,
      name: json['name'] as String,
    );
  }
}

class ExtensionSourceInfo {
  final String name;
  final String language;
  final String id;
  final String baseUrl;

  const ExtensionSourceInfo({
    required this.name,
    required this.language,
    required this.id,
    required this.baseUrl,
  });

  factory ExtensionSourceInfo.fromJson(Map<String, dynamic> json) {
    return ExtensionSourceInfo(
      name: (json['name'] ?? 'Unknown source').toString(),
      language: (json['lang'] ?? 'unknown').toString(),
      id: (json['id'] ?? '').toString(),
      baseUrl: (json['baseUrl'] ?? '').toString(),
    );
  }
}

class ExtensionEntry {
  final String name;
  final String packageName;
  final String apkFile;
  final String language;
  final int versionCode;
  final String version;
  final bool isNsfw;
  final List<ExtensionSourceInfo> sources;
  final String repositoryUrl;
  final String? directApkUrl;
  final String? iconUrl;

  const ExtensionEntry({
    required this.name,
    required this.packageName,
    required this.apkFile,
    required this.language,
    required this.versionCode,
    required this.version,
    required this.isNsfw,
    required this.sources,
    required this.repositoryUrl,
    this.directApkUrl,
    this.iconUrl,
  });

  factory ExtensionEntry.fromJson(
    Map<String, dynamic> json, {
    required String repositoryUrl,
  }) {
    final rawSources = json['sources'];
    final sources = rawSources is List
        ? rawSources.whereType<Map>().map((item) => ExtensionSourceInfo.fromJson(
              Map<String, dynamic>.from(item),
            )).toList(growable: false)
        : <ExtensionSourceInfo>[];
    final rawCode = json['code'];
    final versionCode = rawCode is num
        ? rawCode.toInt()
        : int.tryParse(rawCode?.toString() ?? '') ?? 0;

    return ExtensionEntry(
      name: (json['name'] ?? 'Unnamed extension').toString(),
      packageName: (json['pkg'] ?? '').toString(),
      apkFile: (json['apk'] ?? '').toString(),
      language: (json['lang'] ?? 'unknown').toString(),
      versionCode: versionCode,
      version: (json['version'] ?? 'Unknown').toString(),
      isNsfw: json['nsfw'] == 1 || json['nsfw'] == true,
      sources: sources,
      repositoryUrl: repositoryUrl,
      directApkUrl: json['apkUrl']?.toString(),
      iconUrl: json['iconUrl']?.toString(),
    );
  }

  String get apkUrl {
    if (directApkUrl != null && directApkUrl!.isNotEmpty) {
      return directApkUrl!;
    }
    final repositoryUri = Uri.parse(repositoryUrl);
    return repositoryUri.resolve('./apk/$apkFile').toString();
  }

  String get displayLanguage => language.toUpperCase();
}
