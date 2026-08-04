enum PhotoShareOutcome { completed, canceled }

abstract interface class PhotoSharer {
  Future<PhotoShareOutcome> share({required List<String> localPaths});

  Future<void> discard({required List<String> localPaths});
}
