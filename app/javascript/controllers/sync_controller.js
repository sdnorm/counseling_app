// app/javascript/controllers/sync_controller.js
import { Controller } from "@hotwired/stimulus";
import { encrypt, decrypt } from "lib/crypto";
import { readDataKey, exportState, mergeState, writeAccountStamp } from "lib/db";
import { signOut } from "lib/session";

export default class extends Controller {
  connect() {
    this.key = null;
    this.unlocked = false;
    this.saveHandler = () => this.save();
    // Logout flushes through this handshake before wiping the device, so a
    // failed upload can block the wipe instead of destroying unsynced data.
    this.flushHandler = async () => {
      const ok = await this.save();
      document.dispatchEvent(new CustomEvent("sync:flushed", { detail: { ok } }));
    };
    // A bfcache restore would revive the unlocked DOM (decrypted entries)
    // after logout. Force a clean boot instead.
    this.pageshowHandler = (event) => {
      if (event.persisted) window.location.reload();
    };
    // iOS Safari pans the whole page up to keep a focused input above the
    // keyboard and sometimes never pans back after the keyboard closes,
    // leaving the page stuck half off-screen. Once the visual viewport is
    // back to full height, snap the scroll position home.
    this.viewportHandler = () => {
      const vv = window.visualViewport;
      if (vv.height >= window.innerHeight - 1 && (window.scrollY > 0 || vv.offsetTop > 0)) {
        window.scrollTo(0, 0);
      }
    };
    document.addEventListener("sync:save", this.saveHandler);
    document.addEventListener("sync:flush", this.flushHandler);
    window.addEventListener("pageshow", this.pageshowHandler);
    window.visualViewport?.addEventListener("resize", this.viewportHandler);
    this.boot();
  }

  disconnect() {
    document.removeEventListener("sync:save", this.saveHandler);
    document.removeEventListener("sync:flush", this.flushHandler);
    window.removeEventListener("pageshow", this.pageshowHandler);
    window.visualViewport?.removeEventListener("resize", this.viewportHandler);
  }

  // Login is the only gate: the device either holds the data key or it
  // doesn't. The server copy only decides what to merge; losing the network
  // must not lock a user out of entries that are already on the device.
  async boot() {
    try {
      this.key = await readDataKey();
      if (!this.key) return signOut();

      const response = await fetch("/api/sync", {
        headers: { "Accept": "application/json" },
        credentials: "same-origin",
        cache: "no-store"
      });
      if (response.status === 401) return signOut();
      if (response.status === 404) {
        // Fresh account: nothing to import yet.
        const { account } = await response.json().catch(() => ({}));
        if (account !== undefined) await writeAccountStamp(account);
        return this.markUnlocked();
      }
      if (!response.ok) return this.markUnlocked();

      const blob = await response.json();
      let plaintext;
      try {
        plaintext = await decrypt(blob.ciphertext, blob.nonce, this.key);
      } catch {
        // The blob was re-keyed by a password reset on another device. This
        // device's key is dead, and nothing here is uploaded first, so the
        // newer blob survives.
        return signOut({ reason: "changed" });
      }
      await mergeState(plaintext);
      await writeAccountStamp(blob.account);
      this.markUnlocked();
    } catch (e) {
      console.error("Sync load failed, using local data:", e);
      this.markUnlocked();
    }
  }

  markUnlocked() {
    this.unlocked = true;
    document.dispatchEvent(new CustomEvent("app:unlocked", { bubbles: true }));
  }

  async save() {
    // Locked means the screens never rendered, so nothing new was written.
    if (!this.key || !this.unlocked) return true;

    // Abort rather than hang so every caller gets a settled answer, and no
    // upload is left in flight for a later logout navigation to kill.
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 10000);
    try {
      const state = await exportState();
      const { ciphertext, nonce } = await encrypt(state, this.key);

      const response = await fetch("/api/sync", {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        credentials: "same-origin",
        signal: abort.signal,
        body: JSON.stringify({ blob: { ciphertext, nonce } })
      });

      // A rejected save means this entry exists only on this device. Say so
      // rather than letting the backup silently fall behind.
      if (!response.ok) this.warnSaveFailed(response.status);
      return response.ok;
    } catch (error) {
      this.warnSaveFailed(error);
      return false;
    } finally {
      clearTimeout(timer);
    }
  }

  warnSaveFailed(reason) {
    console.error("Sync save failed:", reason);
    const el = document.getElementById("flash-container");
    if (!el) return;
    el.innerHTML = '<div class="flash">Saved on this device, but not backed up. Check your connection.</div>';
    setTimeout(() => { el.innerHTML = ""; }, 4000);
  }

  clear() {
    this.key = null;
    this.unlocked = false;
  }
}
