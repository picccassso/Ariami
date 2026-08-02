import 'dart:math';

/// Service for managing shuffle functionality
/// Implements true random shuffle using Fisher-Yates algorithm
class ShuffleService<T> {
  final Random _random = Random();

  List<T> _originalQueue = [];
  List<T> _shuffledQueue = [];
  bool _isShuffled = false;

  /// Check if shuffle is enabled
  bool get isShuffled => _isShuffled;

  /// Get original queue (unshuffled order)
  List<T> get originalQueue => List.unmodifiable(_originalQueue);

  /// Get shuffled queue
  List<T> get shuffledQueue => List.unmodifiable(_shuffledQueue);

  /// Get current queue (shuffled or original)
  List<T> get currentQueue => _isShuffled ? _shuffledQueue : _originalQueue;

  /// Positional permutation into [activeQueue] that reconstructs the stored
  /// pre-shuffle order. Identity matching keeps equal-valued duplicate
  /// occurrences distinct.
  List<int> backingOrderFor(List<T> activeQueue) {
    if (!_isShuffled || _originalQueue.length != activeQueue.length) {
      return List<int>.generate(activeQueue.length, (index) => index);
    }
    final unmatched = activeQueue.indexed.map((entry) => entry.$1).toSet();
    final order = <int>[];
    for (final original in _originalQueue) {
      int? index;
      for (final candidate in unmatched) {
        if (identical(activeQueue[candidate], original)) {
          index = candidate;
          break;
        }
      }
      if (index == null) {
        for (final candidate in unmatched) {
          if (activeQueue[candidate] == original) {
            index = candidate;
            break;
          }
        }
      }
      if (index == null) {
        return List<int>.generate(activeQueue.length, (value) => value);
      }
      unmatched.remove(index);
      order.add(index);
    }
    return order;
  }

  /// Restores a shuffled queue received over Connect without randomizing it
  /// again. Both lists must contain the same positional occurrences.
  void restoreShuffled({
    required List<T> originalQueue,
    required List<T> shuffledQueue,
  }) {
    _originalQueue = List<T>.from(originalQueue);
    _shuffledQueue = List<T>.from(shuffledQueue);
    _isShuffled = true;
  }

  int indexOfOccurrence(List<T> queue, T item) =>
      _indexOfOccurrence(queue, item);

  /// Enable shuffle
  /// Keeps the current item at position, shuffles the rest
  List<T> enableShuffle(List<T> queue, T? currentItem) {
    if (queue.isEmpty) {
      return [];
    }

    // Store original queue
    _originalQueue = List.from(queue);
    _isShuffled = true;

    // Create a copy for shuffling
    final queueCopy = List<T>.from(queue);

    // If there's a current item, find and remove it
    if (currentItem != null) {
      final currentIndex = _indexOfOccurrence(queueCopy, currentItem);
      if (currentIndex != -1) queueCopy.removeAt(currentIndex);
    }

    // Shuffle using Fisher-Yates algorithm
    _fisherYatesShuffle(queueCopy);

    // Create shuffled queue with current item at the start
    if (currentItem != null) {
      _shuffledQueue = [currentItem, ...queueCopy];
    } else {
      _shuffledQueue = queueCopy;
    }

    return _shuffledQueue;
  }

  /// Disable shuffle
  /// Returns to original order, maintaining current item position
  List<T> disableShuffle(T? currentItem) {
    _isShuffled = false;

    if (currentItem == null || _originalQueue.isEmpty) {
      return _originalQueue;
    }

    // Find index of current item in original queue
    final currentIndex = _indexOfOccurrence(_originalQueue, currentItem);

    if (currentIndex == -1) {
      // Current item not in original queue, return as is
      return _originalQueue;
    }

    // Return original queue
    return _originalQueue;
  }

  /// Reconciles both shuffle representations after the active queue changes.
  ///
  /// Identity matches run before equality matches so removing one of several
  /// equal-valued occurrences removes that exact occurrence. Existing items
  /// retain their original unshuffled order; newly queued items are appended.
  void synchronizeQueue(List<T> activeQueue) {
    if (!_isShuffled) return;

    final unmatchedActive =
        activeQueue.indexed.map((entry) => entry.$1).toSet();
    final matchedByOriginalIndex = <int, T>{};

    void match(bool Function(T candidate, T original) matches) {
      for (var originalIndex = 0;
          originalIndex < _originalQueue.length;
          originalIndex++) {
        if (matchedByOriginalIndex.containsKey(originalIndex)) continue;
        final original = _originalQueue[originalIndex];
        int? activeIndex;
        for (final candidateIndex in unmatchedActive) {
          if (matches(activeQueue[candidateIndex], original)) {
            activeIndex = candidateIndex;
            break;
          }
        }
        if (activeIndex == null) continue;
        matchedByOriginalIndex[originalIndex] = activeQueue[activeIndex];
        unmatchedActive.remove(activeIndex);
      }
    }

    match(identical);
    match((candidate, original) => candidate == original);

    final synchronizedOriginal = <T>[];
    for (var index = 0; index < _originalQueue.length; index++) {
      if (matchedByOriginalIndex.containsKey(index)) {
        synchronizedOriginal.add(matchedByOriginalIndex[index] as T);
      }
    }
    for (final index in unmatchedActive) {
      synchronizedOriginal.add(activeQueue[index]);
    }
    _originalQueue = synchronizedOriginal;
    _shuffledQueue = List<T>.from(activeQueue);
  }

  /// Toggle shuffle on/off
  List<T> toggleShuffle(List<T> queue, T? currentItem) {
    if (_isShuffled) {
      return disableShuffle(currentItem);
    } else {
      return enableShuffle(queue, currentItem);
    }
  }

  /// Fisher-Yates shuffle algorithm
  /// Guarantees uniform distribution of permutations
  void _fisherYatesShuffle(List<T> list) {
    for (int i = list.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  /// Get next item in queue
  T? getNextItem(T currentItem) {
    final queue = currentQueue;
    if (queue.isEmpty) return null;

    final currentIndex = _indexOfOccurrence(queue, currentItem);
    if (currentIndex == -1 || currentIndex >= queue.length - 1) {
      return null; // No next item
    }

    return queue[currentIndex + 1];
  }

  /// Get previous item in queue
  T? getPreviousItem(T currentItem) {
    final queue = currentQueue;
    if (queue.isEmpty) return null;

    final currentIndex = _indexOfOccurrence(queue, currentItem);
    if (currentIndex <= 0) {
      return null; // No previous item
    }

    return queue[currentIndex - 1];
  }

  /// Reset the shuffle service
  void reset() {
    _originalQueue = [];
    _shuffledQueue = [];
    _isShuffled = false;
  }

  int _indexOfOccurrence(List<T> queue, T item) {
    final identicalIndex =
        queue.indexWhere((candidate) => identical(candidate, item));
    return identicalIndex == -1 ? queue.indexOf(item) : identicalIndex;
  }
}
