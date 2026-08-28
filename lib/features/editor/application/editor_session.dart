import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/legacy_edit_recipe_adapter.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';

class EditorSession extends ChangeNotifier {
  EditorSession({EditRecipe? initialRecipe})
    : _recipe = initialRecipe ?? EditRecipe.neutral;

  final List<EditRecipe> _history = [];
  final List<EditRecipe> _redoHistory = [];
  EditRecipe _recipe;
  EditRecipe? _adjustmentStart;
  List<String> _prioritizedMetaOpIds = const [];
  PlatformMetaOpCapabilities _platformCapabilities =
      metaOpCapabilitiesForTargetPlatform(defaultTargetPlatform);

  static const _editingCore = EditingCore();
  static const _legacyAdapter = LegacyEditRecipeAdapter();

  EditRecipe get recipe => _recipe;
  bool get canUndo => _history.isNotEmpty;
  bool get canRedo => _redoHistory.isNotEmpty;
  bool get isEdited => _recipe != EditRecipe.neutral;

  void setPlatformCapabilities(PlatformMetaOpCapabilities capabilities) {
    if (identical(_platformCapabilities, capabilities)) return;
    _platformCapabilities = capabilities;
    notifyListeners();
  }

  Set<String> availableManualMetaOpIds({
    Set<String> applicability = const {'photo'},
  }) => metaOpAvailability(applicability: applicability).manualIds.toSet();

  List<String> orderedManualMetaOpIds({
    Set<String> applicability = const {'photo'},
  }) {
    final available = metaOpAvailability(
      applicability: applicability,
    ).manualIds;
    final admitted = available.toSet();
    return List.unmodifiable([
      ..._prioritizedMetaOpIds.where(admitted.contains),
      ...available.where((id) => !_prioritizedMetaOpIds.contains(id)),
    ]);
  }

  MetaOpAvailability metaOpAvailability({
    Set<String> applicability = const {'photo'},
  }) => MetaOpAvailability.resolve(
    catalog: MetaOpCatalog.standard,
    capabilities: _platformCapabilities,
    policy: standardMetaOpProductPolicy,
    applicability: applicability,
  );

  List<String> searchAvailableMetaOps(
    String query, {
    Set<String> applicability = const {'photo'},
  }) => metaOpAvailability(
    applicability: applicability,
  ).search(MetaOpCatalog.standard, query);

  EditContext editContext({
    Set<String> photoIds = const {},
    Set<String> targetIds = const {},
    Set<String> applicability = const {'photo'},
    Set<String> resourceIds = const {},
    Map<String, int> resourceByteLengths = const {},
  }) => EditContext(
    platform: _platformCapabilities.platform,
    photoIds: photoIds,
    targetIds: targetIds,
    applicability: applicability,
    resourceIds: resourceIds,
    resourceByteLengths: resourceByteLengths,
    metaOpCapabilities: _platformCapabilities,
  );

  void load(
    EditRecipe recipe, {
    Iterable<String> prioritizedMetaOpIds = const [],
  }) {
    final priorities = prioritizedMetaOpIds.toSet().toList(growable: false);
    final changed =
        _recipe != recipe ||
        _history.isNotEmpty ||
        !listEquals(_prioritizedMetaOpIds, priorities);
    _history.clear();
    _redoHistory.clear();
    _adjustmentStart = null;
    _recipe = recipe;
    _prioritizedMetaOpIds = priorities;
    if (changed) {
      notifyListeners();
    }
  }

  void apply(EditRecipe nextRecipe) {
    if (nextRecipe == _recipe) {
      return;
    }
    _history.add(_recipe);
    _redoHistory.clear();
    _recipe = nextRecipe;
    notifyListeners();
  }

  /// Changes only the active portrait editing target. Target focus is UI
  /// state until an actual parameter adjustment commits the resulting recipe.
  void selectPortraitTarget(EditRecipe nextRecipe) {
    if (nextRecipe == _recipe) return;
    _adjustmentStart = null;
    _recipe = nextRecipe;
    notifyListeners();
  }

  void beginAdjustment() {
    _adjustmentStart ??= _recipe;
  }

  void preview(EditRecipe nextRecipe) {
    if (_adjustmentStart == null) {
      throw StateError('beginAdjustment must be called before preview');
    }
    if (nextRecipe == _recipe) {
      return;
    }
    _recipe = nextRecipe;
    notifyListeners();
  }

  EditResult previewMetaOp(OpAddress address, Object value) {
    final start = _adjustmentStart;
    if (start == null) {
      throw StateError('beginAdjustment must be called before previewMetaOp');
    }
    final state = _legacyAdapter.read(start);
    final result = _editingCore.apply(
      state: state,
      transaction: EditTransaction(
        id: 'preview-${address.metaOpId}',
        baseVersion: state.version,
        source: EditSource.manual,
        changes: [MetaOpChange(address: address, value: value)],
      ),
      context: EditContext(
        platform: _platformCapabilities.platform,
        photoIds: {?address.photoId},
        targetIds: {?address.targetId},
        metaOpCapabilities: _platformCapabilities,
      ),
    );
    if (result is! AcceptedEdit) return result;
    final nextRecipe = _legacyAdapter.writeKnownValue(
      recipe: _recipe,
      address: address,
      state: result.state,
    );
    if (nextRecipe != _recipe) {
      _recipe = nextRecipe;
      notifyListeners();
    }
    return result;
  }

  EditResult applyMetaOp(OpAddress address, Object value) {
    final state = _legacyAdapter.read(_recipe);
    final result = _editingCore.apply(
      state: state,
      transaction: EditTransaction(
        id: 'apply-${address.metaOpId}',
        baseVersion: state.version,
        source: EditSource.manual,
        changes: [MetaOpChange(address: address, value: value)],
      ),
      context: EditContext(
        platform: _platformCapabilities.platform,
        photoIds: {?address.photoId},
        targetIds: {?address.targetId},
        metaOpCapabilities: _platformCapabilities,
      ),
    );
    if (result is! AcceptedEdit) return result;
    apply(
      _legacyAdapter.writeKnownValue(
        recipe: _recipe,
        address: address,
        state: result.state,
      ),
    );
    return result;
  }

  void commitAdjustment() {
    final start = _adjustmentStart;
    if (start == null) {
      return;
    }
    _adjustmentStart = null;
    if (start != _recipe) {
      _history.add(start);
      _redoHistory.clear();
      notifyListeners();
    }
  }

  void cancelAdjustment() {
    final start = _adjustmentStart;
    if (start == null) return;
    _adjustmentStart = null;
    if (_recipe != start) {
      _recipe = start;
      notifyListeners();
    }
  }

  void undo() {
    _adjustmentStart = null;
    if (_history.isEmpty) {
      return;
    }
    _redoHistory.add(_recipe);
    _recipe = _history.removeLast();
    notifyListeners();
  }

  void redo() {
    _adjustmentStart = null;
    if (_redoHistory.isEmpty) {
      return;
    }
    _history.add(_recipe);
    _recipe = _redoHistory.removeLast();
    notifyListeners();
  }

  void reset() {
    _adjustmentStart = null;
    apply(EditRecipe.neutral);
  }
}
