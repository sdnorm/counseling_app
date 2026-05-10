const DB_NAME = "crossroads_app";
const DB_VERSION = 1;

function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      db.createObjectStore("profile", { keyPath: "id" });
      db.createObjectStore("journalEntries", { keyPath: "id" });
      db.createObjectStore("gratitudeEntries", { keyPath: "id" });
      db.createObjectStore("emotionSnapshots", { keyPath: "id" });
      db.createObjectStore("copingSkills", { keyPath: "text" });
      db.createObjectStore("triangleSnaps", { keyPath: "id" });
      db.createObjectStore("checkinEntries", { keyPath: "id" });
      db.createObjectStore("takeaways", { keyPath: "id" });
      db.createObjectStore("agendaItems", { keyPath: "id" });
      db.createObjectStore("settings", { keyPath: "id" });
    };
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
  const stores = [
    "profile", "journalEntries", "gratitudeEntries", "emotionSnapshots",
    "copingSkills", "triangleSnaps", "checkinEntries", "takeaways",
    "agendaItems", "settings"
  ];
  const state = {};
  for (const store of stores) {
    state[store] = await getAll(store);
  }
  return JSON.stringify(state);
}

export async function importState(json) {
  const state = JSON.parse(json);
  for (const [store, items] of Object.entries(state)) {
    for (const item of items) {
      await put(store, item);
    }
  }
}
