// Tiny IndexedDB store for library snapshots ('kv') and cached artwork
// thumbnails ('artwork'). Works over plain-HTTP LAN and Tailscale, unlike
// Cache Storage, and holds far more than localStorage.
(() => {
  const MAX_ARTWORK_ENTRIES = 2500;
  let dbPromise;
  let writesSincePrune = 0;

  function db() {
    dbPromise ??= new Promise((resolve, reject) => {
      const req = indexedDB.open('ariami', 2);
      req.onupgradeneeded = () => {
        const d = req.result;
        if (!d.objectStoreNames.contains('kv')) {
          d.createObjectStore('kv');
        }
        if (!d.objectStoreNames.contains('artwork')) {
          const art = d.createObjectStore('artwork');
          art.createIndex('ts', 'ts', { unique: false });
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
    return dbPromise;
  }

  function run(storeName, mode, op) {
    return db().then((d) => new Promise((resolve, reject) => {
      const tx = d.transaction(storeName, mode);
      const req = op(tx.objectStore(storeName));
      tx.oncomplete = () => resolve(req ? (req.result ?? null) : null);
      tx.onerror = tx.onabort = () => reject(tx.error);
    }));
  }

  async function maybePruneArtwork() {
    if (++writesSincePrune < 100) return;
    writesSincePrune = 0;
    try {
      const d = await db();
      await new Promise((resolve, reject) => {
        const tx = d.transaction('artwork', 'readwrite');
        const store = tx.objectStore('artwork');
        const countReq = store.count();
        countReq.onsuccess = () => {
          let excess = countReq.result - MAX_ARTWORK_ENTRIES;
          if (excess <= 0) return;
          const idx = store.index('ts');
          idx.openCursor().onsuccess = (e) => {
            const cursor = e.target.result;
            if (cursor && excess > 0) {
              cursor.delete();
              excess--;
              cursor.continue();
            }
          };
        };
        tx.oncomplete = () => resolve();
        tx.onerror = tx.onabort = () => reject(tx.error);
      });
    } catch (_) {}
  }

  window.ariamiStore = {
    read: (key) => run('kv', 'readonly', (s) => s.get(key)),
    write: (key, value) => run('kv', 'readwrite', (s) => s.put(value, key)),

    readArtwork: async (key) => {
      const entry = await run('artwork', 'readonly', (s) => s.get(key));
      if (!entry || !entry.bytes) return null;
      return entry.bytes instanceof Uint8Array
        ? entry.bytes
        : new Uint8Array(entry.bytes);
    },

    writeArtwork: async (key, bytes) => {
      await run('artwork', 'readwrite', (s) =>
        s.put({ bytes, ts: Date.now() }, key),
      );
      maybePruneArtwork();
    },

    clearArtwork: () => run('artwork', 'readwrite', (s) => s.clear()),
  };
})();
