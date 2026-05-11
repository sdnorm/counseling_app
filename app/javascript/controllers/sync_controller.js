import { Controller } from "@hotwired/stimulus";
import { deriveKey, encrypt, decrypt } from "lib/crypto";
import { exportState, importState } from "lib/db";

export default class extends Controller {
  connect() {
    this.key = null;
    this.salt = null;
  }

  async load(password) {
    const response = await fetch("/api/sync", {
      headers: { "Accept": "application/json" }
    });

    if (response.status === 404) {
      this.salt = window.crypto.getRandomValues(new Uint8Array(16));
      this.key = await deriveKey(password, this.salt);
      return;
    }

    const blob = await response.json();
    this.salt = new Uint8Array(atob(blob.salt).split("").map(c => c.charCodeAt(0)));
    this.key = await deriveKey(password, this.salt);

    const plaintext = await decrypt(blob.ciphertext, blob.nonce, this.key);
    await importState(plaintext);
  }

  async save() {
    if (!this.key) return;

    const state = await exportState();
    const { ciphertext, nonce } = await encrypt(state, this.key);

    await fetch("/api/sync", {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify({
        blob: {
          ciphertext,
          nonce,
          salt: btoa(String.fromCharCode(...this.salt))
        }
      })
    });
  }

  clear() {
    this.key = null;
    this.salt = null;
  }
}
