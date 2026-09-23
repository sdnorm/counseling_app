// app/javascript/controllers/password_reset_controller.js
import { Controller } from "@hotwired/stimulus";
import {
  MIN_PASSWORD_LENGTH, derivePasswordKeys, deriveRecoveryWrappingKey,
  generateRecoveryCode, generateDataKey, wrapDataKey, unwrapDataKey, lockDataKey
} from "lib/keys";
import { encrypt } from "lib/crypto";
import { requestJSON } from "lib/request";
import { readAccountStamp, writeAccountStamp, writeDataKey, exportState, clearData } from "lib/db";

// Three outcomes, decided before submit and shown as a warning:
//   code   — the recovery code unwraps the data key; nothing is lost anywhere.
//   device — no code, but this device holds the account's entries: make a
//            new data key, re-encrypt what's here, replace the server blob.
//   wipe   — no code, nothing local: the backup is erased and they start over.
const WARNINGS = {
  code: "Your entries will be restored on this device.",
  device: "Your entries on this device will be kept. Entries made on other devices since this one last synced won't be included.",
  wipe: "Without your recovery code, your encrypted backup will be permanently erased and you will start fresh."
};

export default class extends Controller {
  static targets = ["password", "code", "warning", "submit", "error"];
  static values = { account: Number, email: String, recoveryWrappedKey: String, token: String };

  async connect() {
    const stamp = await readAccountStamp();
    this.deviceHoldsData = stamp !== null && stamp === this.accountValue;
    this.updateWarning();
  }

  path() {
    if (this.codeTarget.value.trim()) return "code";
    return this.deviceHoldsData ? "device" : "wipe";
  }

  updateWarning() {
    const path = this.path();
    this.warningTarget.textContent = WARNINGS[path];
    this.warningTarget.style.color = path === "wipe" ? "#c0392b" : "";
  }

  toggleVisibility(event) {
    this.passwordTarget.type = event.target.checked ? "text" : "password";
  }

  async submit(event) {
    event.preventDefault();
    if (this.busy) return;

    const newPassword = this.passwordTarget.value;
    if (newPassword.length < MIN_PASSWORD_LENGTH) {
      return this.fail(`Use a password of at least ${MIN_PASSWORD_LENGTH} characters.`);
    }
    const path = this.path();

    this.start("Saving…");
    try {
      const email = this.emailValue;
      const { wrappingKey, authHash } = await derivePasswordKeys(newPassword, email);
      const body = { password: authHash };
      let dataKey;
      let recoveryCode = null;

      if (path === "code") {
        const recoveryKey = await deriveRecoveryWrappingKey(this.codeTarget.value, email);
        try {
          dataKey = await unwrapDataKey(this.recoveryWrappedKeyValue, recoveryKey, { extractable: true });
        } catch {
          return this.fail("That recovery code doesn't match.");
        }
        body.recovery_wrapped_key = this.recoveryWrappedKeyValue;
      } else {
        dataKey = await generateDataKey();
        recoveryCode = generateRecoveryCode();
        const recoveryKey = await deriveRecoveryWrappingKey(recoveryCode, email);
        body.recovery_wrapped_key = await wrapDataKey(dataKey, recoveryKey);
        if (path === "device") {
          // Only ciphertext leaves the device, same as every save.
          const { ciphertext, nonce } = await encrypt(await exportState(), dataKey);
          body.blob = { ciphertext, nonce };
        } else {
          body.wipe = true;
        }
      }
      body.password_wrapped_key = await wrapDataKey(dataKey, wrappingKey);

      const { ok, data } = await requestJSON("PATCH", `/passwords/${encodeURIComponent(this.tokenValue)}`, body);
      if (!ok) return this.fail((data.errors || ["Reset failed. Please try again."]).join(" "));
      // An expired token redirects to an HTML page: fetch follows it, so
      // `ok` is true but there is no account in the body.
      if (data.account === undefined) return this.fail("This reset link is invalid or has expired. Request a new one.");

      // Keep local entries only on the device path, or the code path on the
      // device that already holds this account. Anything else is stale or
      // another account's.
      if (path === "wipe" || !this.deviceHoldsData) await clearData();
      await writeDataKey(await lockDataKey(dataKey));
      await writeAccountStamp(data.account);

      if (recoveryCode) {
        this.element.hidden = true;
        document.dispatchEvent(new CustomEvent("recovery-code:show", { detail: { code: recoveryCode, next: "/" } }));
      } else {
        window.location.assign("/");
      }
    } catch (e) {
      console.error("Password reset failed:", e);
      this.fail("Reset failed. Check your connection and try again.");
    } finally {
      this.stop();
    }
  }

  start(label) {
    this.busy = true;
    this.errorTarget.hidden = true;
    this.submitTarget.disabled = true;
    this.submitTarget.value = label;
  }

  stop() {
    this.busy = false;
    this.submitTarget.disabled = false;
    this.submitTarget.value = "Save password";
  }

  fail(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }
}
