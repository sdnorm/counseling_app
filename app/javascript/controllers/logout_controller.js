import { Controller } from "@hotwired/stimulus";
import { wipeAll } from "lib/db";

// Wipes client-side data (IndexedDB + service worker caches) before the
// session DELETE submits, so nothing readable remains on the device.
export default class extends Controller {
  async submit(event) {
    event.preventDefault();
    try {
      await Promise.all([wipeAll(), this.clearServiceWorkerCaches()]);
    } catch (e) {
      console.error("Logout cleanup failed:", e);
    }
    this.element.submit();
  }

  clearServiceWorkerCaches() {
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
}
