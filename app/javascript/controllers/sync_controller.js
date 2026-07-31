import { Controller } from "@hotwired/stimulus";
import { deriveKey, decrypt } from "lib/crypto";
import { importState } from "lib/db";

export default class extends Controller {
  connect() {
    this.key = null;
    this.salt = null;
    this.unlocked = false;
    this.saveHandler = () => this.save();
    // Logout flushes through this handshake before wiping the device, so a
    // failed upload can block the wipe instead of destroying unsynced data.
    this.flushHandler = async () => {
      const ok = await this.save();
      document.dispatchEvent(new CustomEvent("sync:flushed", { detail: { ok } }));
    };
    // A bfcache restore would revive the unlocked DOM (decrypted entries,
    // hidden overlay) after logout. Force a clean boot instead.
    this.pageshowHandler = (event) => {
      if (event.persisted) window.location.reload();
    };
    document.addEventListener("sync:save", this.saveHandler);
    document.addEventListener("sync:flush", this.flushHandler);
    window.addEventListener("pageshow", this.pageshowHandler);
    this.showUnlockScreen();
  }

  disconnect() {
    document.removeEventListener("sync:save", this.saveHandler);
    document.removeEventListener("sync:flush", this.flushHandler);
    window.removeEventListener("pageshow", this.pageshowHandler);
  }

  showUnlockScreen() {
    const overlay = document.getElementById("unlock-overlay");
    const btn = document.getElementById("unlock-btn");
    const input = document.getElementById("unlock-passphrase");
    const error = document.getElementById("unlock-error");

    if (!overlay || !btn || !input) return;

    overlay.style.display = "flex";
    input.value = "";
    error.style.display = "none";

    btn.onclick = async (e) => {
      e.preventDefault();
      const passphrase = input.value;
      if (!passphrase) return;

      const success = await this.unlock(passphrase);
      if (success) {
        overlay.style.display = "none";
        this.unlocked = true;
        document.dispatchEvent(new CustomEvent("app:unlocked", { bubbles: true }));
      } else {
        error.style.display = "block";
        input.value = "";
      }
    };

    input.onkeydown = (e) => {
      if (e.key === "Enter") btn.click();
    };
  }

  async unlock(passphrase) {
    const errorEl = document.getElementById("unlock-error");
    try {
      const response = await fetch("/api/sync", {
        headers: { "Accept": "application/json" },
        credentials: "same-origin"
      });

      if (response.status === 401) {
        document.getElementById("unlock-first-time").style.display = "none";
        errorEl.innerHTML = 'Session expired. <a href="/session/new" style="color:var(--blue);text-decoration:underline;">Log in again</a>.';
        return false;
      }

      if (response.status === 404) {
        // First time user, create new key
        this.salt = window.crypto.getRandomValues(new Uint8Array(16));
        this.key = await deriveKey(passphrase, this.salt);
        errorEl.textContent = "Incorrect passphrase. Please try again.";
        document.getElementById("unlock-first-time").style.display = "block";
        return true;
      }

      document.getElementById("unlock-first-time").style.display = "none";
      const contentType = response.headers.get("content-type") || "";
      if (!contentType.includes("application/json")) {
        errorEl.textContent = "Unexpected server response. Please refresh.";
        return false;
      }

      const blob = await response.json();
      this.salt = new Uint8Array(atob(blob.salt).split("").map(c => c.charCodeAt(0)));
      this.key = await deriveKey(passphrase, this.salt);

      // Try to decrypt to verify passphrase is correct
      const plaintext = await decrypt(blob.ciphertext, blob.nonce, this.key);
      await importState(plaintext);
      errorEl.textContent = "Incorrect passphrase. Please try again.";
      return true;
    } catch (e) {
      console.error("Unlock failed:", e);
      document.getElementById("unlock-first-time").style.display = "none";
      errorEl.textContent = "Incorrect passphrase. Please try again.";
      this.key = null;
      this.salt = null;
      return false;
    }
  }

  async save() {
    // Locked means the screens never rendered, so nothing new was written.
    if (!this.key || !this.unlocked) return true;

    const { exportState } = await import("lib/db");
    const { encrypt } = await import("lib/crypto");

    const state = await exportState();
    const { ciphertext, nonce } = await encrypt(state, this.key);

    try {
      const response = await fetch("/api/sync", {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        credentials: "same-origin",
        body: JSON.stringify({
          blob: {
            ciphertext,
            nonce,
            salt: btoa(String.fromCharCode(...this.salt))
          }
        })
      });

      // A rejected save means this entry exists only on this device. Say so
      // rather than letting the backup silently fall behind.
      if (!response.ok) this.warnSaveFailed(response.status);
      return response.ok;
    } catch (error) {
      this.warnSaveFailed(error);
      return false;
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
    this.salt = null;
    this.unlocked = false;
  }
}
