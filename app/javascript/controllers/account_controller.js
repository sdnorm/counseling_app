// app/javascript/controllers/account_controller.js
import { Controller } from "@hotwired/stimulus";
import {
  MIN_PASSWORD_LENGTH, derivePasswordKeys, deriveRecoveryWrappingKey,
  generateRecoveryCode, wrapDataKey, unwrapDataKey
} from "lib/keys";
import { requestJSON } from "lib/request";

// Both actions re-wrap the data key, which needs an extractable handle, and
// the local copy is deliberately not extractable. So: fetch the
// password-wrapped copy, unwrap it with the current password (which also
// checks the password locally), re-wrap, send. The server verifies the
// current auth hash again before saving anything.
export default class extends Controller {
  static targets = ["currentPassword", "newPassword", "changeButton", "rotatePassword", "rotateButton", "error"];
  static values = { email: String };

  async changePassword() {
    const current = this.currentPasswordTarget.value;
    const next = this.newPasswordTarget.value;
    if (next.length < MIN_PASSWORD_LENGTH) {
      return this.showError(`Use a password of at least ${MIN_PASSWORD_LENGTH} characters.`);
    }

    await this.run(this.changeButtonTarget, async () => {
      const { dataKey, authHash } = await this.unlockWithPassword(current);
      const { wrappingKey, authHash: newAuthHash } = await derivePasswordKeys(next, this.emailValue);
      const { ok, data } = await requestJSON("PUT", "/api/account/keys", {
        current_password: authHash,
        password: newAuthHash,
        password_wrapped_key: await wrapDataKey(dataKey, wrappingKey)
      });
      if (!ok) throw new Error((data.errors || ["Could not change the password."]).join(" "));

      this.currentPasswordTarget.value = "";
      this.newPasswordTarget.value = "";
      this.flash("Password changed.");
    });
  }

  async rotateRecoveryCode() {
    await this.run(this.rotateButtonTarget, async () => {
      const { dataKey, authHash } = await this.unlockWithPassword(this.rotatePasswordTarget.value);
      const code = generateRecoveryCode();
      const recoveryKey = await deriveRecoveryWrappingKey(code, this.emailValue);
      const { ok, data } = await requestJSON("PUT", "/api/account/keys", {
        current_password: authHash,
        recovery_wrapped_key: await wrapDataKey(dataKey, recoveryKey)
      });
      if (!ok) throw new Error((data.errors || ["Could not make a new recovery code."]).join(" "));

      this.rotatePasswordTarget.value = "";
      document.dispatchEvent(new CustomEvent("recovery-code:show", { detail: { code, next: null } }));
    });
  }

  async unlockWithPassword(password) {
    const { wrappingKey, authHash } = await derivePasswordKeys(password, this.emailValue);
    const { ok, data } = await requestJSON("GET", "/api/account/keys");
    if (!ok) throw new Error("Couldn't reach the server. Check your connection.");
    try {
      const dataKey = await unwrapDataKey(data.password_wrapped_key, wrappingKey, { extractable: true });
      return { dataKey, authHash };
    } catch {
      throw new Error("Incorrect current password.");
    }
  }

  async run(button, work) {
    if (this.busy) return;
    this.busy = true;
    button.disabled = true;
    this.errorTarget.hidden = true;
    try {
      await work();
    } catch (e) {
      this.showError(e.message);
    } finally {
      this.busy = false;
      button.disabled = false;
    }
  }

  showError(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }

  flash(text) {
    const el = document.getElementById("flash-container");
    if (!el) return;
    el.innerHTML = `<div class="flash">${text}</div>`;
    setTimeout(() => { el.innerHTML = ""; }, 2200);
  }
}
