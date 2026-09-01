import 'package:yingjian/features/creation/domain/creation_intent.dart';

/// The user-visible goal selected on Home before a source photo is chosen.
///
/// [CreationIntent] remains the execution boundary: the first three tasks are
/// local static-photo work, while [motion] follows the independent generation
/// path. Persisting this choice keeps resumed drafts in the correct workspace.
enum CreationTask {
  optimize(CreationIntent.apply),
  style(CreationIntent.apply),
  cleanup(CreationIntent.apply),
  motion(CreationIntent.motion);

  const CreationTask(this.creationIntent);

  final CreationIntent creationIntent;

  static CreationTask fromCreationIntent(CreationIntent intent) =>
      switch (intent) {
        CreationIntent.apply => CreationTask.style,
        CreationIntent.motion => CreationTask.motion,
      };
}
