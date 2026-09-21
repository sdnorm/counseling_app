// app/javascript/controllers/login_controller.js
import { Controller } from "@hotwired/stimulus";
import { derivePasswordKeys, unwrapDataKey } from "lib/keys";
import { requestJSON } from "lib/request";
import { readAccountStamp, clearData, writeDataKey, writeAccountStamp } from "lib/db";

export default class extends Controller {
  static targets = ["email", "password", "submit", "error"];

  async submit(event) {
    event.preventDefault();
    if (this.busy) return;

    this.start("Signing in…");
    try {
      const email = this.emailTarget.value;
      const { wrappingKey, authHash } = await derivePasswordKeys(this.passwordTarget.value, email);

      const { ok, status, data } = await requestJSON("POST", "/session", { email_address: email, password: authHash });
      if (status === 429) return this.fail("Too many attempts. Try again later.");
      if (!ok) return this.fail("Try another email address or password.");

      let dataKey;
      try {
        dataKey = await unwrapDataKey(data.password_wrapped_key, wrappingKey);
      } catch {
        // The auth hash matched but the wrapped key didn't: server-side
        // corruption. Don't leave a keyless session behind.
        await requestJSON("DELETE", "/session");
        return this.fail("Something is wrong with your account. Reset your password to continue.");
      }

      // A device that last held another account's entries must not merge
      // them into this one. Same account: keep them, boot merges the server
      // copy over the top.
      const stamp = await readAccountStamp();
      if (stamp !== null && stamp !== data.account) await clearData();
      await writeDataKey(dataKey);
      await writeAccountStamp(data.account);

      window.location.assign("/");
    } catch (e) {
      console.error("Login failed:", e);
      this.fail("Sign in failed. Check your connection and try again.");
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
    this.submitTarget.value = "Sign in";
  }

  fail(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }
}
