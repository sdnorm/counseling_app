const DB_NAME = "crossroads_app";
const DB_VERSION = 2;

// "meta" is bookkeeping, not user content: it is excluded from the synced state
// so it never travels to the server or gets overwritten by an incoming blob.
const STORE_KEY_PATHS = {
  profile: "id",
  journalEntries: "id",
  gratitudeEntries: "id",
  emotionSnapshots: "id",
  copingSkills: "text",
  triangleSnaps: "id",
  checkinEntries: "id",
  takeaways: "id",
  agendaItems: "id",
  settings: "id",
  meta: "id",
};

const DATA_STORES = Object.keys(STORE_KEY_PATHS).filter((name) => name !== "meta");

const ACCOUNT_STAMP = "account";

function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      // Create-if-missing so this covers both a fresh install and an upgrade
      // from v1, which had every store except "meta".
      for (const [name, keyPath] of Object.entries(STORE_KEY_PATHS)) {
        if (!db.objectStoreNames.contains(name)) {
          db.createObjectStore(name, { keyPath });
        }
      }
    };
  });
}

// Which account's data this device is holding, or null if we've never recorded
// it (a fresh install, or one that predates the stamp).
export async function readAccountStamp() {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const request = db.transaction("meta", "readonly").objectStore("meta").get(ACCOUNT_STAMP);
    request.onsuccess = () => resolve(request.result ? request.result.value : null);
    request.onerror = () => reject(request.error);
  });
}

export async function writeAccountStamp(value) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("meta", "readwrite");
    tx.objectStore("meta").put({ id: ACCOUNT_STAMP, value });
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function getAll(storeName) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, "readonly");
    const store = tx.objectStore(storeName);
    const request = store.getAll();
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function put(storeName, data) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, "readwrite");
    const store = tx.objectStore(storeName);
    const request = store.put(data);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function remove(storeName, id) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, "readwrite");
    const store = tx.objectStore(storeName);
    const request = store.delete(id);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

export async function exportState() {
  const state = {};
  for (const store of DATA_STORES) {
    state[store] = await getAll(store);
  }
  return JSON.stringify(state);
}

// Replaces local state wholesale. Use only when the device is known to be
// holding a *different* account's data: every store is cleared first, including
// ones absent from the incoming state, in one transaction so a failure can't
// leave two accounts' records interleaved.
export async function importState(json) {
  return writeState(json, { clearFirst: true });
}

// Merges the incoming state over what's already here, which keeps entries that
// were saved locally but haven't reached the server yet (offline, or a rejected
// save). Safe only when the local data belongs to the same account.
export async function mergeState(json) {
  return writeState(json, { clearFirst: false });
}

// Empties the user-data stores but leaves the database (and the account stamp)
// in place. Unlike wipeAll this is safe mid-session: wipeAll deletes the whole
// database, which races with anything that writes straight afterwards.
export async function clearData() {
  return writeState("{}", { clearFirst: true });
}

function writeState(json, { clearFirst }) {
  const state = JSON.parse(json);
  return openDB().then((db) => new Promise((resolve, reject) => {
    const tx = db.transaction(DATA_STORES, "readwrite");
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);

    for (const name of DATA_STORES) {
      const store = tx.objectStore(name);
      if (clearFirst) store.clear();
      for (const item of state[name] || []) {
        store.put(item);
      }
    }
  }));
}

export async function wipeAll() {
  const db = await openDB();
  const stores = Array.from(db.objectStoreNames);
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction(stores, "readwrite");
      stores.forEach((name) => tx.objectStore(name).clear());
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } finally {
    db.close();
    // Best-effort: removes the database entirely once other connections close.
    indexedDB.deleteDatabase(DB_NAME);
  }
}
