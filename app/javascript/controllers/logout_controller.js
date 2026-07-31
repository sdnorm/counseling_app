import { Controller } from "@hotwired/stimulus";
import { wipeAll } from "lib/db";

// Logging out wipes all client-side data (IndexedDB + service worker caches),
// so the encrypted blob on the server must be current first. The flow is:
// flush the sync upload, and if it fails (offline, expired session), make the
// user explicitly choose between staying logged in and discarding the
// un-backed-up changes.
export default class extends Controller {
  async submit(event) {
    event.preventDefault();
    if (this.busy) return;
    this.busy = true;

    const flushed = await this.flushSync();
    if (!flushed && !(await this.confirmDiscard())) {
      this.busy = false;
      return;
    }

    try {
      await Promise.all([wipeAll(), this.clearServiceWorkerCaches()]);
    } catch (e) {
      console.error("Logout cleanup failed:", e);
    }
    this.element.submit();
  }

  // Asks the sync controller to upload now. save() aborts its own request
  // after 10s, so sync:flushed always arrives with a settled verdict; the
  // fallback timer only covers a page with no sync controller mounted.
  flushSync() {
    return new Promise((resolve) => {
      const timer = setTimeout(() => finish(false), 12000);
      const handler = (event) => finish(!!event.detail?.ok);
      const finish = (ok) => {
        clearTimeout(timer);
        document.removeEventListener("sync:flushed", handler);
        resolve(ok);
      };
      document.addEventListener("sync:flushed", handler);
      document.dispatchEvent(new CustomEvent("sync:flush"));
    });
  }

  confirmDiscard() {
    return new Promise((resolve) => {
      document.getElementById("logout-warning")?.remove();
      const box = document.createElement("div");
      box.id = "logout-warning";
      box.className = "tip";
      box.style.cssText = "margin-top:10px;";
      box.innerHTML = `
        <strong>Your latest changes could not be backed up.</strong>
        You may be offline. Logging out will permanently delete anything not
        yet backed up from this device.
        <div style="display:flex;gap:8px;margin-top:8px;">
          <button type="button" class="btn" data-stay>Stay logged in</button>
          <button type="button" class="btn btn-o" data-discard>Log out anyway</button>
        </div>`;
      box.addEventListener("click", (e) => {
        if (e.target.closest("[data-stay]")) { box.remove(); resolve(false); }
        if (e.target.closest("[data-discard]")) { box.remove(); resolve(true); }
      });
      this.element.after(box);
    });
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
