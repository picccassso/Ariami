import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cache_entry.dart';

/// Database layer for managing cache metadata persistence
class CacheDatabase {
  static const String _cacheEntriesKey = 'cache_entries';
  static const String _cacheLimitKey = 'cache_limit_mb';
  static const String _cacheEnabledKey = 'cache_enabled';

  final SharedPreferences _prefs;

  CacheDatabase(this._prefs);

  /// Create instance
  static Future<CacheDatabase> create() async {
    final prefs = await SharedPreferences.getInstance();
    return CacheDatabase(prefs);
  }

  // ============================================================================
  // CACHE ENTRIES MANAGEMENT
  // ============================================================================

  /// Save all cache entries to storage
  Future<void> saveCacheEntries(List<CacheEntry> entries) async {
    final jsonList = entries.map((entry) => jsonEncode(entry.toJson())).toList();
    await _prefs.setStringList(_cacheEntriesKey, jsonList);
  }

  /// Load all cache entries from storage
  Future<List<CacheEntry>> loadCacheEntries() async {
    final jsonList = _prefs.getStringList(_cacheEntriesKey) ?? [];
    return jsonList
        .map((json) => CacheEntry.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();
  }

  /// Get a single cache entry by ID and type
  Future<CacheEntry?> getCacheEntry(String id, CacheType type) async {
    final entries = await loadCacheEntries();
    try {
      return entries.firstWhere((e) => e.id == id && e.type == type);
    } catch (_) {
      return null;
    }
  }

  /// Add or update a cache entry
  Future<void> upsertCacheEntry(CacheEntry entry) async {
    final entries = await loadCacheEntries();
    
    // Remove existing entry with same id and type
    entries.removeWhere((e) => e.id == entry.id && e.type == entry.type);
    
    // Add new entry
    entries.add(entry);
    
    await saveCacheEntries(entries);
  }

  /// Remove a cache entry
  Future<void> removeCacheEntry(String id, CacheType type) async {
    final entries = await loadCacheEntries();
    entries.removeWhere((e) => e.id == id && e.type == type);
    await saveCacheEntries(entries);
  }

  /// Update last accessed time for an entry
  Future<void> touchCacheEntry(String id, CacheType type) async {
    final entries = await loadCacheEntries();
    final index = entries.indexWhere((e) => e.id == id && e.type == type);
    
    if (index != -1) {
      entries[index] = entries[index].touch();
      await saveCacheEntries(entries);
    }
  }

  /// Get entries sorted by last accessed time (oldest first) for LRU eviction
  Future<List<CacheEntry>> getEntriesForEviction() async {
    final entries = await loadCacheEntries();
    entries.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
    return entries;
  }

  /// Get all entries of a specific type
  Future<List<CacheEntry>> getEntriesByType(CacheType type) async {
    final entries = await loadCacheEntries();
    return entries.where((e) => e.type == type).toList();
  }

  /// Clear all cache entries
  Future<void> clearAllCacheEntries() async {
    await _prefs.remove(_cacheEntriesKey);
  }

  /// Clear entries of a specific type
  Future<void> clearEntriesByType(CacheType type) async {
    final entries = await loadCacheEntries();
    entries.removeWhere((e) => e.type == type);
    await saveCacheEntries(entries);
  }

  // ============================================================================
  // CACHE STATISTICS
  // ============================================================================

  /// Get total cache size in bytes
  Future<int> getTotalCacheSize() async {
    final entries = await loadCacheEntries();
    return entries.fold<int>(0, (sum, entry) => sum + entry.size);
  }

  /// Get cache size by type in bytes
  Future<int> getCacheSizeByType(CacheType type) async {
    final entries = await getEntriesByType(type);
    return entries.fold<int>(0, (sum, entry) => sum + entry.size);
  }

  /// Get total cache size in MB
  Future<double> getTotalCacheSizeMB() async {
    final bytes = await getTotalCacheSize();
    return bytes / (1024 * 1024);
  }

  /// Get count of cached items
  Future<int> getCacheCount() async {
    final entries = await loadCacheEntries();
    return entries.length;
  }

  /// Get count by type
  Future<int> getCacheCountByType(CacheType type) async {
    final entries = await getEntriesByType(type);
    return entries.length;
  }

  // ============================================================================
  // CACHE SETTINGS
  // ============================================================================

  /// Set cache limit in MB (default 500MB)
  Future<void> setCacheLimit(int limitMB) async {
    await _prefs.setInt(_cacheLimitKey, limitMB);
  }

  /// Get cache limit in MB
  int getCacheLimit() {
    return _prefs.getInt(_cacheLimitKey) ?? 500; // Default 500MB
  }

  /// Get cache limit in bytes
  int getCacheLimitBytes() {
    return getCacheLimit() * 1024 * 1024;
  }

  /// Set whether caching is enabled
  Future<void> setCacheEnabled(bool enabled) async {
    await _prefs.setBool(_cacheEnabledKey, enabled);
  }

  /// Get whether caching is enabled
  bool isCacheEnabled() {
    return _prefs.getBool(_cacheEnabledKey) ?? true; // Default enabled
  }

  // ============================================================================
  // UTILITY
  // ============================================================================

  /// Check if an item is cached
  Future<bool> isCached(String id, CacheType type) async {
    final entry = await getCacheEntry(id, type);
    return entry != null;
  }
}






