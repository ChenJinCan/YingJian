import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

class EditorSession extends ChangeNotifier {
  EditorSession({EditRecipe? initialRecipe})
    : _recipe = initialRecipe ?? EditRecipe.neutral;

  final List<EditRecipe> _history = [];
  EditRecipe _recipe;
  EditRecipe? _adjustmentStart;

  EditRecipe get recipe => _recipe;
  bool get canUndo => _history.isNotEmpty;
  bool get isEdited => _recipe != EditRecipe.neutral;

  void load(EditRecipe recipe) {
    final changed = _recipe != recipe || _history.isNotEmpty;
    _history.clear();
    _adjustmentStart = null;
    _recipe = recipe;
    if (changed) {
      notifyListeners();
    }
  }

  void apply(EditRecipe nextRecipe) {
    if (nextRecipe == _recipe) {
      return;
    }
    _history.add(_recipe);
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

  void commitAdjustment() {
    final start = _adjustmentStart;
    if (start == null) {
      return;
    }
    _adjustmentStart = null;
    if (start != _recipe) {
      _history.add(start);
      notifyListeners();
    }
  }

  void undo() {
    _adjustmentStart = null;
    if (_history.isEmpty) {
      return;
    }
    _recipe = _history.removeLast();
    notifyListeners();
  }

  void reset() {
    _adjustmentStart = null;
    apply(EditRecipe.neutral);
  }
}
