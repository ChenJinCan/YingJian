import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';
import 'package:yingjian/features/generation/domain/generation_input.dart';
import 'package:yingjian/features/generation/infrastructure/first_party_generation_provider.dart';

void main() {
  test(
    'an empty short-lived bearer token fails before any HTTP request',
    () async {
      var requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        requestCount += 1;
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      });

      await expectLater(
        FirstPartyGenerationProvider.connect(
          baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
          bearerTokenProvider: () async => '   ',
          resultDirectoryProvider: Directory.systemTemp.createTemp,
        ),
        throwsA(isA<GenerationBackendAuthenticationRequired>()),
      );
      expect(requestCount, 0);
    },
  );

  test(
    'capability discovery exposes only enabled first-party offers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer short-token',
        );
        expect(request.uri.path, '/v1/generation-capabilities');
        await writeJson(request.response, HttpStatus.ok, {
          'capabilities': [
            {
              'capability': 'optimizeAiRepair',
              'enabled': true,
              'provider': 'baidu',
              'model': 'image_definition_enhance',
              'recipeVersion': 'optimize-ai-repair@1',
              'providerCancelable': false,
              'cancelBoundary': 'not_provider_cancelable',
              'offer': {
                'id': 'offer-repair-1',
                'creditCost': 1,
                'expiresAt': '2099-09-01T00:00:00.000Z',
              },
            },
            {
              'capability': 'optimizeOldPhoto',
              'enabled': false,
              'provider': 'volcengine',
              'model': 'lens_opr',
              'recipeVersion': 'optimize-old-photo@1',
              'providerCancelable': false,
              'cancelBoundary': 'not_provider_cancelable',
              'offer': null,
            },
          ],
        });
      });

      final provider = await FirstPartyGenerationProvider.connect(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
        bearerTokenProvider: () async => 'short-token',
        resultDirectoryProvider: Directory.systemTemp.createTemp,
      );

      expect(provider.availableCapabilities, {
        CreationCapability.optimizeAiRepair,
      });
      expect(
        provider.offerFor(CreationCapability.optimizeAiRepair),
        isA<GenerationOffer>()
            .having((offer) => offer.id, 'id', 'offer-repair-1')
            .having((offer) => offer.creditCost, 'creditCost', 1),
      );
      expect(
        () => provider.offerFor(CreationCapability.optimizeOldPhoto),
        throwsA(isA<GenerationCapabilityUnavailable>()),
      );
    },
  );

  test('explicit capability refresh replaces an expiring offer', () async {
    var discoveryCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      expect(request.uri.path, '/v1/generation-capabilities');
      discoveryCount += 1;
      final payload = catalogPayload();
      final capabilities = payload['capabilities']! as List<Object?>;
      final repair = capabilities.first as Map<String, Object?>;
      final offer = repair['offer']! as Map<String, Object?>;
      offer['id'] = 'offer-repair-$discoveryCount';
      await writeJson(request.response, HttpStatus.ok, payload);
    });
    final provider = await connectTo(server);

    expect(
      provider.offerFor(CreationCapability.optimizeAiRepair).id,
      'offer-repair-1',
    );
    await provider.refreshCapabilities();
    expect(discoveryCount, 2);
    expect(
      provider.offerFor(CreationCapability.optimizeAiRepair).id,
      'offer-repair-2',
    );
  });

  test(
    'missing consent fails before private source media is uploaded',
    () async {
      var uploadCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        if (request.uri.path == '/v1/generation-capabilities') {
          await writeJson(request.response, HttpStatus.ok, catalogPayload());
          return;
        }
        uploadCount += 1;
        await writeJson(request.response, HttpStatus.internalServerError, {});
      });
      final source = await temporaryImage(const [1, 2, 3, 4]);
      addTearDown(() => source.parent.delete(recursive: true));
      final provider = await connectTo(server);

      await expectLater(
        provider.create(
          snapshot: sourceSnapshot(source, CreationCapability.optimizeAiRepair),
          clientRequestId: 'request-no-consent',
          consent: null,
        ),
        throwsA(isA<GenerationConsentRequired>()),
      );
      expect(uploadCount, 0);
    },
  );

  test('an unverified style fingerprint fails before source upload', () async {
    var requestCountAfterCatalog = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      if (request.uri.path == '/v1/generation-capabilities') {
        await writeJson(request.response, HttpStatus.ok, catalogPayload());
        return;
      }
      requestCountAfterCatalog += 1;
      await writeJson(request.response, HttpStatus.internalServerError, {});
    });
    final source = await temporaryImage(const [5, 6]);
    addTearDown(() => source.parent.delete(recursive: true));
    final provider = await connectTo(server);

    await expectLater(
      provider.create(
        snapshot: sourceSnapshot(
          source,
          CreationCapability.styleAiRedraw,
          input: StyleRedrawGenerationInput(
            confirmedDefinition: '用户确认的风格',
            definitionFingerprint: 'a' * 64,
          ),
        ),
        clientRequestId: 'request-bad-style-fingerprint',
        consent: consentFor('styleAiRedraw'),
      ),
      throwsA(isA<GenerationProtocolViolation>()),
    );
    expect(requestCountAfterCatalog, 0);
  });

  test(
    'explicit AI repair uploads privately and creates the selected task',
    () async {
      const sourceBytes = [1, 2, 3, 4, 5];
      final sourceSha = ContentSha256.ofBytes(sourceBytes);
      var uploadCount = 0;
      var taskCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer short-token',
        );
        if (request.uri.path == '/v1/generation-capabilities') {
          await writeJson(request.response, HttpStatus.ok, catalogPayload());
          return;
        }
        if (request.uri.path == '/v1/private-media') {
          uploadCount += 1;
          expect(
            await request.fold<List<int>>([], (a, b) => a..addAll(b)),
            sourceBytes,
          );
          await writeJson(request.response, HttpStatus.created, {
            'media': {'id': 'private-source-1', 'sha256': sourceSha},
          });
          return;
        }
        if (request.uri.path == '/v1/generation-tasks') {
          taskCount += 1;
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body, {
            'creationId': 'request-repair-1',
            'capability': 'optimizeAiRepair',
            'sourceMediaId': 'private-source-1',
            'sourceOriginalSha256': sourceSha,
            'sourceUploadSha256': sourceSha,
            'consent': {
              'offerId': 'offer-optimizeAiRepair',
              'uploadConfirmed': true,
              'costConfirmed': true,
              'policyVersion': 3,
            },
          });
          await writeJson(request.response, HttpStatus.created, {
            'task': taskPayload(
              id: 'task-repair-1',
              requestId: 'request-repair-1',
              capability: 'optimizeAiRepair',
              sourceMediaId: 'private-source-1',
              sourceSha256: sourceSha,
              provider: 'baidu',
              model: 'image_definition_enhance',
            ),
          });
          return;
        }
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      });
      final source = await temporaryImage(sourceBytes);
      addTearDown(() => source.parent.delete(recursive: true));
      final provider = await connectTo(server);

      final job = await provider.create(
        snapshot: sourceSnapshot(source, CreationCapability.optimizeAiRepair),
        clientRequestId: 'request-repair-1',
        consent: GenerationConsent(
          offerId: 'offer-optimizeAiRepair',
          uploadConfirmed: true,
          costConfirmed: true,
          policyVersion: 3,
          confirmedAt: DateTime.utc(2026, 9, 1),
        ),
      );

      expect(uploadCount, 1);
      expect(taskCount, 1);
      expect(job.id, 'task-repair-1');
      expect(job.clientRequestId, 'request-repair-1');
      expect(job.sourceSha256, sourceSha);
      expect(job.capability, CreationCapability.optimizeAiRepair);
      expect(job.state, GenerationJobState.queued);
    },
  );

  test(
    'old-photo mode is explicit and preserved in the backend identity',
    () async {
      final source = await temporaryImage(const [10, 11]);
      addTearDown(() => source.parent.delete(recursive: true));
      final sourceSha = ContentSha256.ofBytes(await source.readAsBytes());
      final server = await explicitInputServer(
        capability: 'optimizeOldPhoto',
        sourceSha: sourceSha,
        expectedTaskFields: {'colorMode': 'preserve'},
        inputIdentity: 'old-photo-v1:preserve',
        provider: 'volcengine',
        model: 'lens_opr',
      );
      addTearDown(server.close);
      final provider = await connectTo(server);

      final job = await provider.create(
        snapshot: sourceSnapshot(
          source,
          CreationCapability.optimizeOldPhoto,
          input: const OldPhotoGenerationInput(
            colorMode: OldPhotoColorMode.preserve,
          ),
        ),
        clientRequestId: 'request-explicit',
        consent: consentFor('optimizeOldPhoto'),
      );

      expect(job.inputIdentity, 'old-photo-v1:preserve');
    },
  );

  test('AI redraw sends only the user-confirmed style definition', () async {
    const definition = '用户确认的克制电影感';
    final definitionSha = ContentSha256.ofBytes(utf8.encode(definition));
    final source = await temporaryImage(const [20, 21]);
    addTearDown(() => source.parent.delete(recursive: true));
    final sourceSha = ContentSha256.ofBytes(await source.readAsBytes());
    final server = await explicitInputServer(
      capability: 'styleAiRedraw',
      sourceSha: sourceSha,
      expectedTaskFields: {
        'styleDefinition': definition,
        'styleDefinitionConfirmed': true,
      },
      inputIdentity: 'style-redraw-v1:$definitionSha',
      provider: 'alibaba',
      model: 'wan2.7-image',
    );
    addTearDown(server.close);
    final provider = await connectTo(server);

    final job = await provider.create(
      snapshot: sourceSnapshot(
        source,
        CreationCapability.styleAiRedraw,
        input: StyleRedrawGenerationInput(
          confirmedDefinition: definition,
          definitionFingerprint: definitionSha,
        ),
      ),
      clientRequestId: 'request-explicit',
      consent: consentFor('styleAiRedraw'),
    );

    expect(job.inputIdentity, 'style-redraw-v1:$definitionSha');
  });

  test('remove passerby uploads the exact confirmed mask separately', () async {
    const sourceBytes = [30, 31];
    const maskBytes = [40, 41, 42];
    final source = await temporaryImage(sourceBytes);
    final mask = File('${source.parent.path}/mask.png')
      ..writeAsBytesSync(maskBytes);
    addTearDown(() => source.parent.delete(recursive: true));
    final sourceSha = ContentSha256.ofBytes(sourceBytes);
    final maskSha = ContentSha256.ofBytes(maskBytes);
    var uploadCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      if (request.uri.path == '/v1/generation-capabilities') {
        await writeJson(request.response, HttpStatus.ok, catalogPayload());
        return;
      }
      if (request.uri.path == '/v1/private-media') {
        uploadCount += 1;
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        final expected = uploadCount == 1 ? sourceBytes : maskBytes;
        expect(bytes, expected);
        await writeJson(request.response, HttpStatus.created, {
          'media': {
            'id': uploadCount == 1 ? 'private-source-1' : 'private-mask-1',
            'sha256': ContentSha256.ofBytes(expected),
          },
        });
        return;
      }
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body['maskMediaId'], 'private-mask-1');
      await writeJson(request.response, HttpStatus.created, {
        'task': taskPayload(
          id: 'task-explicit',
          requestId: 'request-explicit',
          capability: 'cleanupRemovePasserby',
          sourceMediaId: 'private-source-1',
          sourceSha256: sourceSha,
          maskUploadSha256: maskSha,
          inputIdentity: 'mask-removal-v1:$maskSha',
          provider: 'alibaba',
          model: 'wanx2.1-imageedit',
        ),
      });
    });
    final provider = await connectTo(server);

    final job = await provider.create(
      snapshot: sourceSnapshot(
        source,
        CreationCapability.cleanupRemovePasserby,
        input: MaskRemovalGenerationInput(
          maskPath: mask.path,
          maskSha256: maskSha,
        ),
      ),
      clientRequestId: 'request-explicit',
      consent: consentFor('cleanupRemovePasserby'),
    );

    expect(uploadCount, 2);
    expect(job.inputIdentity, 'mask-removal-v1:$maskSha');
  });

  test(
    'a succeeded task downloads and verifies private result media',
    () async {
      const sourceBytes = [50, 51];
      final sourceSha = ContentSha256.ofBytes(sourceBytes);
      final resultBytes = pngHeader(width: 2, height: 3);
      final resultSha = ContentSha256.ofBytes(resultBytes);
      final resultDirectory = await Directory.systemTemp.createTemp(
        'yingjian-results-test-',
      );
      addTearDown(() => resultDirectory.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        if (request.uri.path == '/v1/generation-capabilities') {
          await writeJson(request.response, HttpStatus.ok, catalogPayload());
          return;
        }
        if (request.uri.path == '/v1/private-media' &&
            request.method == 'POST') {
          await request.drain<void>();
          await writeJson(request.response, HttpStatus.created, {
            'media': {'id': 'private-source-1', 'sha256': sourceSha},
          });
          return;
        }
        if (request.uri.path == '/v1/generation-tasks') {
          await request.drain<void>();
          await writeJson(request.response, HttpStatus.created, {
            'task': taskPayload(
              id: 'task-result',
              requestId: 'request-result',
              capability: 'optimizeAiRepair',
              sourceMediaId: 'private-source-1',
              sourceSha256: sourceSha,
              provider: 'baidu',
              model: 'image_definition_enhance',
              state: 'succeeded',
              resultMediaId: 'private-result-1',
            ),
          });
          return;
        }
        if (request.uri.path == '/v1/private-media/private-result-1') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('image', 'png')
            ..headers.set('x-content-sha256', resultSha)
            ..add(resultBytes);
          await request.response.close();
          return;
        }
      });
      final source = await temporaryImage(sourceBytes);
      addTearDown(() => source.parent.delete(recursive: true));
      final provider = await FirstPartyGenerationProvider.connect(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
        bearerTokenProvider: () async => 'short-token',
        resultDirectoryProvider: () async => resultDirectory,
      );

      final job = await provider.create(
        snapshot: sourceSnapshot(source, CreationCapability.optimizeAiRepair),
        clientRequestId: 'request-result',
        consent: consentFor('optimizeAiRepair'),
      );

      expect(job.state, GenerationJobState.succeeded);
      expect(job.output, isNotNull);
      expect(job.output!.id, 'private-result-1');
      expect(job.output!.contentSha256, resultSha);
      expect(job.output!.width, 2);
      expect(job.output!.height, 3);
      expect(await File(job.output!.localPath).readAsBytes(), resultBytes);
      expect(job.output!.localPath, startsWith(resultDirectory.path));
    },
  );

  test(
    'cancel returns the backend actual state and usage disposition',
    () async {
      final sourceSha = 'a' * 64;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        if (request.uri.path == '/v1/generation-capabilities') {
          await writeJson(request.response, HttpStatus.ok, catalogPayload());
          return;
        }
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/generation-tasks/task-cancel/cancel');
        await request.drain<void>();
        await writeJson(request.response, HttpStatus.ok, {
          'task': taskPayload(
            id: 'task-cancel',
            requestId: 'request-cancel',
            capability: 'styleAiRedraw',
            sourceMediaId: 'private-source-1',
            sourceSha256: sourceSha,
            inputIdentity: 'style-redraw-v1:${'c' * 64}',
            provider: 'alibaba',
            model: 'wan2.7-image',
            state: 'canceled',
            providerCancellation: 'provider_confirmed',
            usageState: 'released',
            usageDisposition: 'release',
          ),
        });
      });
      final provider = await connectTo(server);
      final job = GenerationJob(
        id: 'task-cancel',
        clientRequestId: 'request-cancel',
        projectId: 'project-1',
        sourcePhotoId: 'photo-1',
        sourceSha256: sourceSha,
        inputIdentity: 'style-redraw-v1:${'c' * 64}',
        capability: CreationCapability.styleAiRedraw,
        state: GenerationJobState.queued,
        provider: 'alibaba',
        model: 'wan2.7-image',
        canCancel: true,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      final cancelled = await provider.cancel(job);

      expect(cancelled.state, GenerationJobState.cancelled);
      expect(cancelled.canCancel, false);
      expect(
        cancelled.cancellationDisposition,
        GenerationCancellationDisposition.providerConfirmed,
      );
      expect(cancelled.usageState, GenerationUsageState.released);
      expect(cancelled.usageDisposition, GenerationUsageDisposition.release);
    },
  );

  test(
    'persisted task contract survives disabled discovery without accepting a switch',
    () async {
      final sourceSha = 'a' * 64;
      final inputIdentity = 'style-redraw-v1:${'c' * 64}';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        if (request.uri.path == '/v1/generation-capabilities') {
          await writeJson(request.response, HttpStatus.ok, {
            'capabilities': [
              {'capability': 'styleAiRedraw', 'enabled': false},
            ],
          });
          return;
        }
        if (request.uri.path ==
            '/v1/generation-tasks/task-historical-cancel/cancel') {
          await request.drain<void>();
          await writeJson(request.response, HttpStatus.ok, {
            'task': taskPayload(
              id: 'task-historical-cancel',
              requestId: 'request-historical-cancel',
              capability: 'styleAiRedraw',
              sourceMediaId: 'private-source-1',
              sourceSha256: sourceSha,
              inputIdentity: inputIdentity,
              provider: 'alibaba',
              model: 'wan2.7-image',
              state: 'canceled',
              providerCancellation: 'provider_confirmed',
              usageState: 'released',
              usageDisposition: 'release',
            ),
          });
          return;
        }
        final isSwitched = request.uri.path.endsWith('task-switched');
        await writeJson(request.response, HttpStatus.ok, {
          'task': taskPayload(
            id: isSwitched ? 'task-switched' : 'task-historical-observe',
            requestId: isSwitched
                ? 'request-switched'
                : 'request-historical-observe',
            capability: 'styleAiRedraw',
            sourceMediaId: 'private-source-1',
            sourceSha256: sourceSha,
            inputIdentity: inputIdentity,
            provider: isSwitched ? 'baidu' : 'alibaba',
            model: isSwitched ? 'replacement-model' : 'wan2.7-image',
            state: 'failed',
            usageState: 'released',
            usageDisposition: 'release',
          ),
        });
      });
      final provider = await connectTo(server);
      expect(provider.availableCapabilities, isEmpty);

      GenerationJob historicalJob({
        required String id,
        required String requestId,
        required bool canCancel,
      }) => GenerationJob(
        id: id,
        clientRequestId: requestId,
        projectId: 'project-1',
        sourcePhotoId: 'photo-1',
        sourceSha256: sourceSha,
        inputIdentity: inputIdentity,
        capability: CreationCapability.styleAiRedraw,
        state: GenerationJobState.queued,
        provider: 'alibaba',
        model: 'wan2.7-image',
        canCancel: canCancel,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      final cancelled = await provider.cancel(
        historicalJob(
          id: 'task-historical-cancel',
          requestId: 'request-historical-cancel',
          canCancel: true,
        ),
      );
      expect(cancelled.state, GenerationJobState.cancelled);
      expect(cancelled.provider, 'alibaba');
      expect(cancelled.model, 'wan2.7-image');

      final observed = await provider
          .observe(
            historicalJob(
              id: 'task-historical-observe',
              requestId: 'request-historical-observe',
              canCancel: false,
            ),
          )
          .single;
      expect(observed.state, GenerationJobState.failed);
      expect(observed.provider, 'alibaba');
      expect(observed.model, 'wan2.7-image');

      await expectLater(
        provider
            .observe(
              historicalJob(
                id: 'task-switched',
                requestId: 'request-switched',
                canCancel: false,
              ),
            )
            .first,
        throwsA(isA<GenerationProtocolViolation>()),
      );
    },
  );

  test('observe rejects a task update whose source identity changed', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      if (request.uri.path == '/v1/generation-capabilities') {
        await writeJson(request.response, HttpStatus.ok, catalogPayload());
        return;
      }
      expect(request.uri.path, '/v1/generation-tasks/task-observe');
      await writeJson(request.response, HttpStatus.ok, {
        'task': taskPayload(
          id: 'task-observe',
          requestId: 'request-observe',
          capability: 'optimizeAiRepair',
          sourceMediaId: 'private-source-other',
          sourceSha256: 'b' * 64,
          provider: 'baidu',
          model: 'image_definition_enhance',
          state: 'running',
        ),
      });
    });
    final provider = await connectTo(server);
    final job = GenerationJob(
      id: 'task-observe',
      clientRequestId: 'request-observe',
      projectId: 'project-1',
      sourcePhotoId: 'photo-1',
      sourceSha256: 'a' * 64,
      capability: CreationCapability.optimizeAiRepair,
      state: GenerationJobState.queued,
      provider: 'baidu',
      model: 'image_definition_enhance',
      canCancel: false,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

    await expectLater(
      provider.observe(job).first,
      throwsA(isA<GenerationProtocolViolation>()),
    );
  });

  test(
    'the same explicit client request creates at most one backend task',
    () async {
      const sourceBytes = [60, 61];
      final sourceSha = ContentSha256.ofBytes(sourceBytes);
      var uploadCount = 0;
      var taskCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        if (request.uri.path == '/v1/generation-capabilities') {
          await writeJson(request.response, HttpStatus.ok, catalogPayload());
          return;
        }
        if (request.uri.path == '/v1/private-media') {
          uploadCount += 1;
          await request.drain<void>();
          await writeJson(request.response, HttpStatus.created, {
            'media': {'id': 'private-source-1', 'sha256': sourceSha},
          });
          return;
        }
        taskCount += 1;
        await request.drain<void>();
        await writeJson(request.response, HttpStatus.created, {
          'task': taskPayload(
            id: 'task-idempotent',
            requestId: 'request-idempotent',
            capability: 'optimizeAiRepair',
            sourceMediaId: 'private-source-1',
            sourceSha256: sourceSha,
            provider: 'baidu',
            model: 'image_definition_enhance',
          ),
        });
      });
      final source = await temporaryImage(sourceBytes);
      addTearDown(() => source.parent.delete(recursive: true));
      final provider = await connectTo(server);
      final snapshot = sourceSnapshot(
        source,
        CreationCapability.optimizeAiRepair,
      );

      final first = await provider.create(
        snapshot: snapshot,
        clientRequestId: 'request-idempotent',
        consent: consentFor('optimizeAiRepair'),
      );
      final second = await provider.create(
        snapshot: snapshot,
        clientRequestId: 'request-idempotent',
        consent: consentFor('optimizeAiRepair'),
      );

      expect(second.id, first.id);
      expect(uploadCount, 1);
      expect(taskCount, 1);
    },
  );
}

List<int> pngHeader({required int width, required int height}) => [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0,
  0,
  0,
  13,
  0x49,
  0x48,
  0x44,
  0x52,
  (width >> 24) & 0xff,
  (width >> 16) & 0xff,
  (width >> 8) & 0xff,
  width & 0xff,
  (height >> 24) & 0xff,
  (height >> 16) & 0xff,
  (height >> 8) & 0xff,
  height & 0xff,
];

Future<HttpServer> explicitInputServer({
  required String capability,
  required String sourceSha,
  required Map<String, Object?> expectedTaskFields,
  required String inputIdentity,
  required String provider,
  required String model,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/v1/generation-capabilities') {
      await writeJson(request.response, HttpStatus.ok, catalogPayload());
      return;
    }
    if (request.uri.path == '/v1/private-media') {
      await request.drain<void>();
      await writeJson(request.response, HttpStatus.created, {
        'media': {'id': 'private-source-1', 'sha256': sourceSha},
      });
      return;
    }
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    for (final entry in expectedTaskFields.entries) {
      expect(body[entry.key], entry.value);
    }
    await writeJson(request.response, HttpStatus.created, {
      'task': taskPayload(
        id: 'task-explicit',
        requestId: 'request-explicit',
        capability: capability,
        sourceMediaId: 'private-source-1',
        sourceSha256: sourceSha,
        inputIdentity: inputIdentity,
        provider: provider,
        model: model,
      ),
    });
  });
  return server;
}

GenerationConsent consentFor(String capability) => GenerationConsent(
  offerId: 'offer-$capability',
  uploadConfirmed: true,
  costConfirmed: true,
  policyVersion: 3,
  confirmedAt: DateTime.utc(2026, 9, 1),
);

Future<FirstPartyGenerationProvider> connectTo(HttpServer server) =>
    FirstPartyGenerationProvider.connect(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      bearerTokenProvider: () async => 'short-token',
      resultDirectoryProvider: Directory.systemTemp.createTemp,
    );

Map<String, Object?> catalogPayload() => {
  'capabilities': [
    for (final capability in const [
      'optimizeAiRepair',
      'optimizeOldPhoto',
      'styleAiRedraw',
      'cleanupRemovePasserby',
      'cleanupBrushRemove',
    ])
      {
        'capability': capability,
        'enabled': true,
        'provider': capability == 'optimizeAiRepair'
            ? 'baidu'
            : capability == 'optimizeOldPhoto'
            ? 'volcengine'
            : 'alibaba',
        'model': capability == 'optimizeAiRepair'
            ? 'image_definition_enhance'
            : capability == 'optimizeOldPhoto'
            ? 'lens_opr'
            : capability == 'styleAiRedraw'
            ? 'wan2.7-image'
            : 'wanx2.1-imageedit',
        'recipeVersion': '$capability@1',
        'providerCancelable':
            capability.startsWith('cleanup') || capability == 'styleAiRedraw',
        'cancelBoundary':
            capability.startsWith('cleanup') || capability == 'styleAiRedraw'
            ? 'provider_pending_only'
            : 'not_provider_cancelable',
        'offer': {
          'id': 'offer-$capability',
          'creditCost': 1,
          'expiresAt': '2099-09-01T00:00:00.000Z',
        },
      },
  ],
};

Map<String, Object?> taskPayload({
  required String id,
  required String requestId,
  required String capability,
  required String sourceMediaId,
  required String sourceSha256,
  required String provider,
  required String model,
  String? inputIdentity,
  String? maskUploadSha256,
  String state = 'pending',
  bool providerCancelable = false,
  String? providerCancellation,
  String usageState = 'reserved',
  String usageDisposition = 'hold',
  String? resultMediaId,
}) => {
  'id': id,
  'requestId': requestId,
  'creationId': requestId,
  'capability': capability,
  'colorMode': null,
  'offerId': 'offer-$capability',
  'sourceMediaId': sourceMediaId,
  'sourceSha256': sourceSha256,
  'maskUploadSha256': ?maskUploadSha256,
  'inputIdentity': inputIdentity,
  'recipeVersion': '$capability@1',
  'provider': provider,
  'model': model,
  'state': state,
  'providerStatus': state == 'pending' ? 'PENDING' : 'SUCCEEDED',
  'providerCancelable': providerCancelable,
  'providerCancellation':
      providerCancellation ??
      (providerCancelable ? 'available_while_pending' : 'not_available'),
  'usageState': usageState,
  'usageDisposition': usageDisposition,
  'resultMediaId': resultMediaId,
  'errorCode': null,
  'createdAt': '2026-09-01T00:00:00.000Z',
  'updatedAt': '2026-09-01T00:00:01.000Z',
};

GenerationSourceSnapshot sourceSnapshot(
  File source,
  CreationCapability capability, {
  GenerationInput? input,
}) => GenerationSourceSnapshot(
  projectId: 'project-1',
  sourcePhotoId: 'photo-1',
  sourcePath: source.path,
  sourceSha256: ContentSha256.ofBytes(source.readAsBytesSync()),
  capability: capability,
  createdAt: DateTime.utc(2026, 9, 1),
  input: input,
);

Future<File> temporaryImage(List<int> bytes) async {
  final directory = await Directory.systemTemp.createTemp(
    'yingjian-provider-test-',
  );
  return File('${directory.path}/source.jpg')..writeAsBytesSync(bytes);
}

Future<void> writeJson(HttpResponse response, int status, Object body) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}
