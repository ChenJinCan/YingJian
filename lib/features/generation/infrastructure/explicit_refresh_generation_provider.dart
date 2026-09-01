import 'dart:async';

import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';

typedef GenerationProviderConnector = Future<GenerationProvider> Function();

/// Keeps a configured first-party provider reconnectable without doing any
/// background retry, provider selection, or capability substitution.
///
/// The connector is invoked only when the user-facing flow explicitly calls
/// [refreshCapabilities]. App startup never creates a session, probes a cloud
/// provider, uploads media, or spends credits. Job and request identities pass
/// through unchanged.
final class ExplicitRefreshGenerationProvider implements GenerationProvider {
  ExplicitRefreshGenerationProvider({
    required GenerationProviderConnector connector,
    GenerationProvider? initialProvider,
  }) : this._(connector, initialProvider);

  ExplicitRefreshGenerationProvider._(this._connector, this._delegate);

  final GenerationProviderConnector _connector;
  GenerationProvider? _delegate;
  Future<void>? _refresh;

  @override
  Set<CreationCapability> get availableCapabilities =>
      _delegate?.availableCapabilities ?? const {};

  @override
  Future<void> refreshCapabilities() {
    final active = _refresh;
    if (active != null) return active;

    final refresh = _refreshOnce();
    _refresh = refresh;
    return refresh.whenComplete(() {
      if (identical(_refresh, refresh)) _refresh = null;
    });
  }

  Future<void> _refreshOnce() async {
    final current = _delegate;
    if (current != null) {
      await current.refreshCapabilities();
      return;
    }

    final connected = await _connector();
    _delegate = connected;
  }

  @override
  GenerationOffer offerFor(CreationCapability capability) {
    final current = _delegate;
    if (current == null) throw GenerationCapabilityUnavailable(capability);
    return current.offerFor(capability);
  }

  @override
  Future<GenerationJob> create({
    required GenerationSourceSnapshot snapshot,
    required String clientRequestId,
    required GenerationConsent? consent,
  }) {
    final current = _delegate;
    if (current == null) {
      return Future.error(GenerationCapabilityUnavailable(snapshot.capability));
    }
    return current.create(
      snapshot: snapshot,
      clientRequestId: clientRequestId,
      consent: consent,
    );
  }

  @override
  Future<GenerationJob> cancel(GenerationJob job) {
    final current = _delegate;
    if (current == null) {
      return Future.error(GenerationCannotCancel(job.id));
    }
    return current.cancel(job);
  }

  @override
  Stream<GenerationJob> observe(GenerationJob job) {
    final current = _delegate;
    if (current == null) {
      return Stream.error(GenerationCapabilityUnavailable(job.capability));
    }
    return current.observe(job);
  }
}
