import 'dart:convert';
import 'dart:io';

import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';

typedef GenerationJobDirectoryProvider = Future<Directory> Function();

final class JsonGenerationJobStore
    implements GenerationJobStore, GenerationProjectDeletionCleanupStore {
  factory JsonGenerationJobStore({
    required GenerationJobDirectoryProvider directory,
  }) => JsonGenerationJobStore._(directory);

  JsonGenerationJobStore._(this._directory);

  static const schemaVersion = 2;

  final GenerationJobDirectoryProvider _directory;

  Future<void> _cleanupStoreTail = Future.value();

  @override
  Future<void> stageProjectDeletionCleanup(String projectId) =>
      _serializeCleanupStore(() async {
        _validateProjectId(projectId);
        final root = await _directory();
        final file = _projectDeletionCleanupFile(root);
        final pending = await _readProjectDeletionCleanups(file);
        if (!pending.add(projectId)) return;
        await _writeProjectDeletionCleanups(file, pending);
      });

  @override
  Future<Set<String>> findPendingProjectDeletionCleanups() =>
      _serializeCleanupStore(() async {
        final root = await _directory();
        return Set.unmodifiable(
          await _readProjectDeletionCleanups(_projectDeletionCleanupFile(root)),
        );
      });

  @override
  Future<void> completeProjectDeletionCleanup(String projectId) =>
      _serializeCleanupStore(() async {
        _validateProjectId(projectId);
        final root = await _directory();
        final file = _projectDeletionCleanupFile(root);
        final pending = await _readProjectDeletionCleanups(file);
        if (!pending.remove(projectId)) return;
        await _writeProjectDeletionCleanups(file, pending);
      });

  @override
  Future<GenerationJob?> findByClientRequestId(String clientRequestId) async {
    final jobs = await _loadJobs();
    for (final job in jobs) {
      if (job.clientRequestId == clientRequestId) return job;
    }
    return null;
  }

  @override
  Future<GenerationJob?> findById(String id) async {
    final jobs = await _loadJobs();
    for (final job in jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  @override
  Future<List<GenerationJob>> findByProjectId(String projectId) async =>
      List.unmodifiable(
        (await _loadJobs()).where((job) => job.projectId == projectId),
      );

  @override
  Future<GenerationJob?> findLatest(
    GenerationRequestIdentity identity, {
    Set<GenerationJobState>? states,
    bool includeAnyInput = false,
  }) async {
    final matches =
        (await _loadJobs())
            .where(
              (job) =>
                  identity.matches(job, includeAnyInput: includeAnyInput) &&
                  (states == null || states.contains(job.state)),
            )
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return matches.firstOrNull;
  }

  @override
  Future<GenerationRequestReservation?> findReservation(
    GenerationRequestIdentity identity,
  ) async {
    final root = await _directory();
    final reservations = await _readReservations(_reservationFile(root));
    return reservations
        .where((reservation) => reservation.identity == identity)
        .firstOrNull;
  }

  @override
  Future<void> saveReservation(GenerationRequestReservation reservation) async {
    final root = await _directory();
    final file = _reservationFile(root);
    final reservations = await _readReservations(file);
    reservations.removeWhere(
      (candidate) =>
          candidate.identity == reservation.identity ||
          candidate.clientRequestId == reservation.clientRequestId,
    );
    reservations.add(reservation);
    await _writeReservations(file, reservations);
  }

  @override
  Future<void> deleteReservation(String clientRequestId) async {
    final root = await _directory();
    final file = _reservationFile(root);
    final reservations = await _readReservations(file);
    final previousLength = reservations.length;
    reservations.removeWhere(
      (reservation) => reservation.clientRequestId == clientRequestId,
    );
    if (reservations.length == previousLength) return;
    await _writeReservations(file, reservations);
  }

  @override
  Future<void> deleteProjectState(String projectId) async {
    final root = await _directory();
    final file = _storeFile(root);
    final jobs = await _readJobs(file);
    final projectJobs = jobs
        .where((job) => job.projectId == projectId)
        .toList(growable: false);
    for (final job in projectJobs) {
      final output = job.output;
      if (output != null) {
        await _deleteOwnedGeneratedFile(root, output.localPath);
      }
    }
    jobs.removeWhere((job) => job.projectId == projectId);
    await _writeJobs(file, jobs);

    final reservationFile = _reservationFile(root);
    final reservations = await _readReservations(reservationFile);
    final previousLength = reservations.length;
    reservations.removeWhere(
      (reservation) => reservation.identity.projectId == projectId,
    );
    if (reservations.length != previousLength) {
      await _writeReservations(reservationFile, reservations);
    }
  }

  @override
  Future<void> save(GenerationJob job) async {
    final root = await _directory();
    final file = _storeFile(root);
    final jobs = await _readJobs(file);
    final existingIndex = jobs.indexWhere(
      (candidate) => candidate.id == job.id,
    );
    if (existingIndex < 0) {
      jobs.add(job);
    } else {
      jobs[existingIndex] = job;
    }

    await _writeJobs(file, jobs);
  }

  static Future<void> _writeJobs(File file, List<GenerationJob> jobs) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'schemaVersion': schemaVersion,
          'jobs': jobs.map(_encodeJob).toList(growable: false),
        }),
        flush: true,
      );
      await _readJobs(temporary);
      await temporary.rename(file.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  static Future<void> _deleteOwnedGeneratedFile(
    Directory root,
    String path,
  ) async {
    final file = File(path);
    if (!await file.exists()) return;
    final resolvedFile = await file.resolveSymbolicLinks();
    for (final directoryName in const [
      'generation-results',
      'upscale-results',
      'motion-results',
    ]) {
      final allowed = Directory('${root.path}/$directoryName');
      if (!await allowed.exists()) continue;
      final resolvedAllowed = await allowed.resolveSymbolicLinks();
      final prefix = resolvedAllowed.endsWith(Platform.pathSeparator)
          ? resolvedAllowed
          : '$resolvedAllowed${Platform.pathSeparator}';
      if (resolvedFile.startsWith(prefix)) {
        await file.delete();
        return;
      }
    }
  }

  Future<List<GenerationJob>> _loadJobs() async {
    final root = await _directory();
    return _readJobs(_storeFile(root));
  }

  static File _storeFile(Directory root) =>
      File('${root.path}/generation/jobs.json');

  static File _reservationFile(Directory root) =>
      File('${root.path}/generation/request-reservations.json');

  static File _projectDeletionCleanupFile(Directory root) =>
      File('${root.path}/generation/project-deletion-cleanups.json');

  Future<T> _serializeCleanupStore<T>(Future<T> Function() operation) {
    final result = _cleanupStoreTail.then((_) => operation());
    _cleanupStoreTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  static void _validateProjectId(String projectId) {
    if (projectId.trim().isEmpty || projectId.length > 512) {
      throw ArgumentError.value(projectId, 'projectId');
    }
  }

  static Future<Set<String>> _readProjectDeletionCleanups(File file) async {
    if (!await file.exists()) return <String>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
      throw const FormatException(
        'Unsupported generation project deletion cleanup store',
      );
    }
    final values = decoded['projectIds'];
    if (values is! List<Object?>) {
      throw const FormatException(
        'Generation project deletion cleanup store requires a list',
      );
    }
    final projectIds = <String>{};
    for (final value in values) {
      if (value is! String || value.trim().isEmpty || value.length > 512) {
        throw const FormatException(
          'Generation project deletion cleanup identities must be strings',
        );
      }
      if (!projectIds.add(value)) {
        throw const FormatException(
          'Generation project deletion cleanup identities must be unique',
        );
      }
    }
    return projectIds;
  }

  static Future<void> _writeProjectDeletionCleanups(
    File file,
    Set<String> projectIds,
  ) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      final sortedIds = projectIds.toList()..sort();
      await temporary.writeAsString(
        jsonEncode({'schemaVersion': 1, 'projectIds': sortedIds}),
        flush: true,
      );
      await _readProjectDeletionCleanups(temporary);
      await temporary.rename(file.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  static Future<List<GenerationRequestReservation>> _readReservations(
    File file,
  ) async {
    if (!await file.exists()) return <GenerationRequestReservation>[];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
      throw const FormatException(
        'Unsupported generation request reservation store',
      );
    }
    final values = decoded['reservations'];
    if (values is! List<Object?>) {
      throw const FormatException(
        'Generation request reservation store requires a list',
      );
    }
    final reservations = <GenerationRequestReservation>[];
    final identities = <GenerationRequestIdentity>{};
    final requestIds = <String>{};
    for (final value in values) {
      if (value is! Map<String, Object?>) {
        throw const FormatException(
          'Generation request reservations must be JSON objects',
        );
      }
      final reservation = _decodeReservation(value);
      if (!identities.add(reservation.identity) ||
          !requestIds.add(reservation.clientRequestId)) {
        throw const FormatException(
          'Generation request reservation identities must be unique',
        );
      }
      reservations.add(reservation);
    }
    return reservations;
  }

  static Future<void> _writeReservations(
    File file,
    List<GenerationRequestReservation> reservations,
  ) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'reservations': reservations
              .map(_encodeReservation)
              .toList(growable: false),
        }),
        flush: true,
      );
      await _readReservations(temporary);
      await temporary.rename(file.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  static Map<String, Object> _encodeReservation(
    GenerationRequestReservation reservation,
  ) => {
    'clientRequestId': reservation.clientRequestId,
    'projectId': reservation.identity.projectId,
    'sourcePhotoId': reservation.identity.sourcePhotoId,
    'sourceSha256': reservation.identity.sourceSha256,
    'capability': reservation.identity.capability.persistedId,
    'inputIdentity': ?reservation.identity.inputIdentity,
    'createdAt': reservation.createdAt.toUtc().toIso8601String(),
  };

  static GenerationRequestReservation _decodeReservation(
    Map<String, Object?> value,
  ) => GenerationRequestReservation(
    clientRequestId: _requiredString(value, 'clientRequestId'),
    identity: GenerationRequestIdentity(
      projectId: _requiredString(value, 'projectId'),
      sourcePhotoId: _requiredString(value, 'sourcePhotoId'),
      sourceSha256: _requiredString(value, 'sourceSha256'),
      capability: CreationCapability.fromPersistedId(
        _requiredString(value, 'capability'),
      ),
      inputIdentity: value['inputIdentity'] as String?,
    ),
    createdAt: _requiredDate(value, 'createdAt'),
  );

  static Future<List<GenerationJob>> _readJobs(File file) async {
    if (!await file.exists()) return <GenerationJob>[];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Generation job store must be a JSON object');
    }
    final storedVersion = decoded['schemaVersion'];
    if (storedVersion is! num ||
        storedVersion.toInt() != storedVersion ||
        (storedVersion.toInt() < 1 || storedVersion.toInt() > schemaVersion)) {
      throw FormatException(
        'Unsupported generation job store schema $storedVersion',
      );
    }
    final values = decoded['jobs'];
    if (values is! List<Object?>) {
      throw const FormatException('Generation job store requires a job list');
    }

    final jobs = <GenerationJob>[];
    final ids = <String>{};
    final requestIds = <String>{};
    for (final value in values) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('Generation jobs must be JSON objects');
      }
      final job = _decodeJob(value);
      if (!ids.add(job.id) || !requestIds.add(job.clientRequestId)) {
        throw const FormatException('Generation job identities must be unique');
      }
      jobs.add(job);
    }
    return jobs;
  }

  static Map<String, Object> _encodeJob(GenerationJob job) => {
    'id': job.id,
    'clientRequestId': job.clientRequestId,
    'projectId': job.projectId,
    'sourcePhotoId': job.sourcePhotoId,
    'sourceSha256': job.sourceSha256,
    'sourceUploadSha256': ?job.sourceUploadSha256,
    'maskUploadSha256': ?job.maskUploadSha256,
    'inputIdentity': ?job.inputIdentity,
    'capability': job.capability.persistedId,
    'state': job.state.name,
    'provider': job.provider,
    'model': job.model,
    'canCancel': job.canCancel,
    'createdAt': job.createdAt.toUtc().toIso8601String(),
    'updatedAt': job.updatedAt.toUtc().toIso8601String(),
    if (job.cancellationDisposition case final value?)
      'cancellationDisposition': value.name,
    if (job.usageState case final value?) 'usageState': value.name,
    if (job.usageDisposition case final value?) 'usageDisposition': value.name,
    if (job.output case final output?) 'output': _encodeOutput(output),
  };

  static Map<String, Object> _encodeOutput(GeneratedMedia output) => {
    'id': output.id,
    'kind': output.kind.name,
    'localPath': output.localPath,
    'contentSha256': output.contentSha256,
    'width': output.width,
    'height': output.height,
    if (output.duration case final duration?)
      'durationMilliseconds': duration.inMilliseconds,
    'savedAssetId': ?output.savedAssetId,
  };

  static GenerationJob _decodeJob(Map<String, Object?> value) {
    final capabilityId = _requiredString(value, 'capability');
    final stateName = _requiredString(value, 'state');
    final state = GenerationJobState.values
        .where((candidate) => candidate.name == stateName)
        .firstOrNull;
    if (state == null) {
      throw FormatException('Unsupported generation job state $stateName');
    }
    final canCancel = value['canCancel'];
    if (canCancel is! bool) {
      throw const FormatException('Generation job canCancel must be a boolean');
    }

    return GenerationJob(
      id: _requiredString(value, 'id'),
      clientRequestId: _requiredString(value, 'clientRequestId'),
      projectId: _requiredString(value, 'projectId'),
      sourcePhotoId: _requiredString(value, 'sourcePhotoId'),
      sourceSha256: _requiredString(value, 'sourceSha256'),
      sourceUploadSha256: _optionalSha256(value, 'sourceUploadSha256'),
      maskUploadSha256: _optionalSha256(value, 'maskUploadSha256'),
      inputIdentity: value['inputIdentity'] as String?,
      capability: CreationCapability.fromPersistedId(capabilityId),
      state: state,
      provider: _requiredString(value, 'provider'),
      model: _requiredString(value, 'model'),
      canCancel: canCancel,
      createdAt: _requiredDate(value, 'createdAt'),
      updatedAt: _requiredDate(value, 'updatedAt'),
      cancellationDisposition: _optionalEnum(
        value,
        'cancellationDisposition',
        GenerationCancellationDisposition.values,
      ),
      usageState: _optionalEnum(
        value,
        'usageState',
        GenerationUsageState.values,
      ),
      usageDisposition: _optionalEnum(
        value,
        'usageDisposition',
        GenerationUsageDisposition.values,
      ),
      output: value['output'] == null
          ? null
          : _decodeOutput(Map<String, Object?>.from(value['output']! as Map)),
    );
  }

  static GeneratedMedia _decodeOutput(Map<String, Object?> value) {
    final kindName = _requiredString(value, 'kind');
    final kind = GeneratedMediaKind.values
        .where((candidate) => candidate.name == kindName)
        .firstOrNull;
    if (kind == null) {
      throw FormatException('Unsupported generated media kind $kindName');
    }
    final width = value['width'];
    final height = value['height'];
    final durationMilliseconds = value['durationMilliseconds'];
    if (width is! int ||
        height is! int ||
        (durationMilliseconds != null && durationMilliseconds is! int)) {
      throw const FormatException(
        'Generated media dimensions and duration must be integers',
      );
    }
    final duration = durationMilliseconds is int
        ? Duration(milliseconds: durationMilliseconds)
        : null;
    return GeneratedMedia(
      id: _requiredString(value, 'id'),
      kind: kind,
      localPath: _requiredString(value, 'localPath'),
      contentSha256: _requiredString(value, 'contentSha256'),
      width: width,
      height: height,
      duration: duration,
      savedAssetId: value['savedAssetId'] as String?,
    );
  }

  static String _requiredString(Map<String, Object?> value, String key) {
    final field = value[key];
    if (field is! String || field.trim().isEmpty) {
      throw FormatException('Generation job $key must be a non-empty string');
    }
    return field;
  }

  static T? _optionalEnum<T extends Enum>(
    Map<String, Object?> value,
    String key,
    List<T> values,
  ) {
    final field = value[key];
    if (field == null) return null;
    if (field is! String) {
      throw FormatException('Generation job $key must be a string');
    }
    final decoded = values
        .where((candidate) => candidate.name == field)
        .firstOrNull;
    if (decoded == null) {
      throw FormatException('Unsupported generation job $key $field');
    }
    return decoded;
  }

  static String? _optionalSha256(Map<String, Object?> value, String key) {
    final field = value[key];
    if (field == null) return null;
    if (field is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(field)) {
      throw FormatException('Generation job $key must be a lowercase SHA-256');
    }
    return field;
  }

  static DateTime _requiredDate(Map<String, Object?> value, String key) {
    final field = _requiredString(value, key);
    final date = DateTime.tryParse(field);
    if (date == null) {
      throw FormatException('Generation job $key must be an ISO-8601 date');
    }
    return date.toUtc();
  }
}
