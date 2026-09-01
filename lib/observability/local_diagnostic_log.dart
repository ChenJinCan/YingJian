import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

typedef DiagnosticDirectoryProvider = Future<Directory> Function();

enum DiagnosticLogLevel { info, warning, error }

final class DiagnosticLogEvent {
  const DiagnosticLogEvent({
    required this.level,
    required this.component,
    required this.operation,
    required this.result,
    this.reason,
    this.itemCount,
    this.durationMs,
  });

  final DiagnosticLogLevel level;
  final String component;
  final String operation;
  final String result;
  final String? reason;
  final int? itemCount;
  final int? durationMs;

  static String reasonFor(Object error) {
    if (error is PlatformException) {
      return 'platform_${_safeToken(error.code)}';
    }
    return _safeToken(error.runtimeType.toString());
  }

  Map<String, Object?> toJson(DateTime timestamp) => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level.name,
    'component': _safeToken(component),
    'operation': _safeToken(operation),
    'result': _safeToken(result),
    if (reason != null) 'reason': _safeToken(reason!),
    if (itemCount != null) 'itemCount': itemCount!.clamp(0, 1000),
    if (durationMs != null) 'durationMs': durationMs!.clamp(0, 3600000),
  };
}

final class DiagnosticLogEntry {
  const DiagnosticLogEntry({
    required this.timestamp,
    required this.level,
    required this.component,
    required this.operation,
    required this.result,
    this.reason,
    this.itemCount,
    this.durationMs,
  });

  factory DiagnosticLogEntry.fromJson(Map<String, Object?> value) {
    return DiagnosticLogEntry(
      timestamp: DateTime.parse(value['timestamp']! as String).toLocal(),
      level: DiagnosticLogLevel.values.byName(value['level']! as String),
      component: value['component']! as String,
      operation: value['operation']! as String,
      result: value['result']! as String,
      reason: value['reason'] as String?,
      itemCount: (value['itemCount'] as num?)?.toInt(),
      durationMs: (value['durationMs'] as num?)?.toInt(),
    );
  }

  final DateTime timestamp;
  final DiagnosticLogLevel level;
  final String component;
  final String operation;
  final String result;
  final String? reason;
  final int? itemCount;
  final int? durationMs;

  String get displayText {
    String two(int value) => value.toString().padLeft(2, '0');
    final time =
        '${timestamp.year}-${two(timestamp.month)}-${two(timestamp.day)} '
        '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}';
    final fields = <String>[
      '$time [${level.name.toUpperCase()}]',
      '$component.$operation',
      'result=$result',
      if (reason != null) 'reason=$reason',
      if (itemCount != null) 'count=$itemCount',
      if (durationMs != null) 'duration_ms=$durationMs',
    ];
    return fields.join(' ');
  }
}

abstract interface class DiagnosticLog {
  void record(DiagnosticLogEvent event);

  Future<List<DiagnosticLogEntry>> readEntries();

  Future<void> clear();

  Future<void> flush();
}

final class FileDiagnosticLog implements DiagnosticLog {
  FileDiagnosticLog({required this.directoryProvider, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _maxFileBytes = 2 * 1024 * 1024;
  static const _maxEntryBytes = 16 * 1024;
  static const _retainedDays = 7;
  static const _maxReadEntries = 500;

  final DiagnosticDirectoryProvider directoryProvider;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();

  @override
  void record(DiagnosticLogEvent event) {
    final timestamp = _now();
    final pending = _tail.then((_) => _append(event, timestamp));
    _tail = pending.catchError((Object _) {
      // Diagnostics must never interrupt the user flow they are observing.
    });
  }

  @override
  Future<void> flush() => _tail;

  @override
  Future<List<DiagnosticLogEntry>> readEntries() async {
    await flush();
    final directory = await _logDirectory();
    if (!await directory.exists()) return const [];
    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.jsonl'))
        .cast<File>()
        .toList();
    files.sort((left, right) => right.path.compareTo(left.path));
    final entries = <DiagnosticLogEntry>[];
    for (final file in files) {
      final lines = await file.readAsLines();
      for (final line in lines.reversed) {
        try {
          final value = jsonDecode(line);
          if (value is Map<String, Object?>) {
            entries.add(DiagnosticLogEntry.fromJson(value));
          } else if (value is Map) {
            entries.add(
              DiagnosticLogEntry.fromJson(Map<String, Object?>.from(value)),
            );
          }
        } on Object {
          // Preserve other readable entries when a partial write is found.
        }
        if (entries.length >= _maxReadEntries) return entries;
      }
    }
    return entries;
  }

  @override
  Future<void> clear() async {
    await flush();
    final directory = await _logDirectory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> _append(DiagnosticLogEvent event, DateTime timestamp) async {
    final directory = await _logDirectory();
    await directory.create(recursive: true);
    await _removeExpiredFiles(directory, timestamp);
    final line = '${jsonEncode(event.toJson(timestamp))}\n';
    if (utf8.encode(line).length > _maxEntryBytes) return;
    final file = File('${directory.path}/${_dateKey(timestamp)}.jsonl');
    final existingBytes = await file.exists() ? await file.length() : 0;
    if (existingBytes + utf8.encode(line).length > _maxFileBytes) return;
    await file.writeAsString(line, mode: FileMode.append, flush: true);
  }

  Future<Directory> _logDirectory() async {
    final root = await directoryProvider();
    return Directory('${root.path}/diagnostic-logs');
  }

  Future<void> _removeExpiredFiles(Directory directory, DateTime now) async {
    final cutoff = now.toUtc().subtract(const Duration(days: _retainedDays));
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      final name = entity.uri.pathSegments.last.split('.').first;
      final date = DateTime.tryParse(name);
      if (date != null &&
          date.isBefore(DateTime.utc(cutoff.year, cutoff.month, cutoff.day))) {
        await entity.delete();
      }
    }
  }

  static String _dateKey(DateTime value) {
    final utc = value.toUtc();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
  }
}

final class MemoryDiagnosticLog implements DiagnosticLog {
  final List<DiagnosticLogEntry> _entries = [];

  @override
  void record(DiagnosticLogEvent event) {
    _entries.insert(
      0,
      DiagnosticLogEntry.fromJson(event.toJson(DateTime.now())),
    );
  }

  @override
  Future<List<DiagnosticLogEntry>> readEntries() async =>
      List.unmodifiable(_entries);

  @override
  Future<void> clear() async => _entries.clear();

  @override
  Future<void> flush() async {}
}

String _safeToken(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_.-]+'), '_')
      .replaceAll(RegExp('_+'), '_');
  if (normalized.isEmpty) return 'unknown';
  return normalized.substring(0, normalized.length.clamp(0, 64));
}
