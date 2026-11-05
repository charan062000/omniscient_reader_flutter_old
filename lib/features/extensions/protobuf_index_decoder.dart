import 'dart:convert';
import 'dart:typed_data';

/// Minimal wire-format reader for Mihon/Anime-extension store index.pb files.
/// Supports both Mihon's source field layout and Aniyomi's torrent/source layout.
class ProtobufIndexDecoder {
  static List<Map<String, dynamic>> decodeExtensions(Uint8List bytes) {
    final root = _fields(bytes);
    final listBytes = _firstBytes(root, 101);
    if (listBytes == null) {
      throw const FormatException('The protobuf index has no embedded extension list.');
    }
    return _decodeList(listBytes);
  }

  static List<Map<String, dynamic>> _decodeList(Uint8List bytes) {
    final result = <Map<String, dynamic>>[];
    for (final field in _fields(bytes)) {
      if (field.number != 1 || field.bytes == null) continue;
      result.add(_decodeExtension(field.bytes!));
    }
    return result;
  }

  static Map<String, dynamic> _decodeExtension(Uint8List bytes) {
    final fields = _fields(bytes);
    final name = _firstString(fields, 1) ?? 'Unnamed extension';
    final packageName = _firstString(fields, 2) ?? '';
    final resourcesBytes = _firstBytes(fields, 3);
    final resources = resourcesBytes == null ? <_Field>[] : _fields(resourcesBytes);
    final apkUrl = _firstString(resources, 1) ?? '';
    final iconUrl = _firstString(resources, 2);
    final versionCode = _firstVarint(fields, 5) ?? 0;
    final version = _firstString(fields, 6) ?? 'Unknown';

    // Mihon uses field 8 for sources. Aniyomi uses field 8 for isTorrent
    // and field 9 for sources. A length-delimited field 8 is Mihon sources.
    final sourceField = fields.where((f) => f.number == 8 && f.bytes != null).toList();
    final aniyomiSources = fields.where((f) => f.number == 9 && f.bytes != null).toList();
    final selectedSources = sourceField.isNotEmpty ? sourceField : aniyomiSources;
    final sources = selectedSources.map((field) => _decodeSource(field.bytes!)).toList();
    final language = sources.isEmpty ? 'unknown' : sources.first['lang'] as String;
    final warning = _firstVarint(fields, 7) ?? 0;

    return <String, dynamic>{
      'name': name,
      'pkg': packageName,
      'apkUrl': apkUrl,
      'iconUrl': iconUrl,
      'lang': language,
      'code': versionCode,
      'version': version,
      'nsfw': warning >= 2,
      'sources': sources,
    };
  }

  static Map<String, dynamic> _decodeSource(Uint8List bytes) {
    final fields = _fields(bytes);
    return <String, dynamic>{
      'id': (_firstVarint(fields, 1) ?? 0).toString(),
      'name': _firstString(fields, 2) ?? 'Unknown source',
      'lang': _firstString(fields, 3) ?? 'unknown',
      'baseUrl': _firstString(fields, 4) ?? '',
    };
  }

  static List<_Field> _fields(Uint8List bytes) {
    final result = <_Field>[];
    var offset = 0;
    while (offset < bytes.length) {
      final key = _readVarint(bytes, offset);
      offset = key.nextOffset;
      final number = key.value >> 3;
      final wireType = key.value & 7;
      if (number == 0) throw const FormatException('Invalid protobuf field number.');
      if (wireType == 0) {
        final value = _readVarint(bytes, offset);
        offset = value.nextOffset;
        result.add(_Field(number, varint: value.value));
      } else if (wireType == 1) {
        if (offset + 8 > bytes.length) throw const FormatException('Truncated protobuf field.');
        offset += 8;
      } else if (wireType == 2) {
        final length = _readVarint(bytes, offset);
        offset = length.nextOffset;
        final end = offset + length.value;
        if (end > bytes.length) throw const FormatException('Truncated protobuf message.');
        result.add(_Field(number, bytes: Uint8List.sublistView(bytes, offset, end)));
        offset = end;
      } else if (wireType == 5) {
        if (offset + 4 > bytes.length) throw const FormatException('Truncated protobuf field.');
        offset += 4;
      } else {
        throw FormatException('Unsupported protobuf wire type: $wireType');
      }
    }
    return result;
  }

  static _Varint _readVarint(Uint8List bytes, int start) {
    var value = 0;
    var shift = 0;
    var offset = start;
    while (offset < bytes.length && shift < 64) {
      final byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return _Varint(value, offset);
      shift += 7;
    }
    throw const FormatException('Invalid protobuf varint.');
  }

  static Uint8List? _firstBytes(List<_Field> fields, int number) {
    for (final field in fields) {
      if (field.number == number && field.bytes != null) return field.bytes;
    }
    return null;
  }

  static String? _firstString(List<_Field> fields, int number) {
    final bytes = _firstBytes(fields, number);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  static int? _firstVarint(List<_Field> fields, int number) {
    for (final field in fields) {
      if (field.number == number && field.varint != null) return field.varint;
    }
    return null;
  }
}

class _Field {
  final int number;
  final int? varint;
  final Uint8List? bytes;
  const _Field(this.number, {this.varint, this.bytes});
}

class _Varint {
  final int value;
  final int nextOffset;
  const _Varint(this.value, this.nextOffset);
}
