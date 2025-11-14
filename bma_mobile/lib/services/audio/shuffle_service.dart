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

  /// Get current queue (shuffled or original)
  List<T> get currentQueue => _isShuffled ? _shuffledQueue : _originalQueue;

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
      queueCopy.remove(currentItem);
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
    final currentIndex = _originalQueue.indexOf(currentItem);

    if (currentIndex == -1) {
      // Current item not in original queue, return as is
      return _originalQueue;
    }

    // Return original queue
    return _originalQueue;
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

    final currentIndex = queue.indexOf(currentItem);
    if (currentIndex == -1 || currentIndex >= queue.length - 1) {
      return null; // No next item
    }

    return queue[currentIndex + 1];
  }

  /// Get previous item in queue
  T? getPreviousItem(T currentItem) {
    final queue = currentQueue;
    if (queue.isEmpty) return null;

    final currentIndex = queue.indexOf(currentItem);
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
}
