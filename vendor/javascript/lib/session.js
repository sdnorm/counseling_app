// vendor/javascript/lib/session.js
import { wipeAll } from "lib/db";
import { requestJSON } from "lib/request";

// Everything that makes a device forget an account: IndexedDB (entries and
// the data key) and the service worker caches. The server session is
// separate; see signOut.
export async function wipeDevice() {
  try {
    await Promise.all([wipeAll(), clearServiceWorkerCaches()]);
  } catch (e) {
    console.error("Device wipe failed:", e);
  }
}

// Wipe, end the server session, land on the login page. `reason` is a short
// token the login page turns into a message (only "changed" exists today).
export async function signOut({ reason } = {}) {
  await wipeDevice();
  await requestJSON("DELETE", "/session").catch(() => {});
  const url = reason ? `/session/new?reason=${encodeURIComponent(reason)}` : "/session/new";
  window.location.replace(url);
}

function clearServiceWorkerCaches() {
  return new Promise((resolve) => {
    const worker = navigator.serviceWorker?.controller;
    if (!worker) return resolve();
    const channel = new MessageChannel();
    const timer = setTimeout(resolve, 1000);
    channel.port1.onmessage = () => {
      clearTimeout(timer);
      resolve();
    };
    worker.postMessage({ type: "logout" }, [channel.port2]);
  });
}
