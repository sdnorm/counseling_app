// app/javascript/controllers/signup_controller.js
import { Controller } from "@hotwired/stimulus";
import {
  MIN_PASSWORD_LENGTH, derivePasswordKeys, deriveRecoveryWrappingKey,
  generateRecoveryCode, generateDataKey, wrapDataKey, lockDataKey
} from "lib/keys";
import { requestJSON } from "lib/request";
import { clearData, writeDataKey, writeAccountStamp } from "lib/db";

export default class extends Controller {
  static targets = ["email", "password", "invite", "submit", "error"];

  toggleVisibility(event) {
    this.passwordTarget.type = event.target.checked ? "text" : "password";
  }

  async submit(event) {
    event.preventDefault();
    if (this.busy) return;

    const email = this.emailTarget.value;
    const password = this.passwordTarget.value;
    if (password.length < MIN_PASSWORD_LENGTH) {
      return this.fail(`Use a password of at least ${MIN_PASSWORD_LENGTH} characters.`);
    }

    this.start("Creating account…");
    try {
      const { wrappingKey, authHash } = await derivePasswordKeys(password, email);
      const recoveryCode = generateRecoveryCode();
      const recoveryKey = await deriveRecoveryWrappingKey(recoveryCode, email);
      const dataKey = await generateDataKey();

      const { ok, data } = await requestJSON("POST", "/users", { user: {
        email_address: email,
        password: authHash,
        invite_code: this.inviteTarget.value,
        password_wrapped_key: await wrapDataKey(dataKey, wrappingKey),
        recovery_wrapped_key: await wrapDataKey(dataKey, recoveryKey)
      } });
      if (!ok) return this.fail((data.errors || ["Sign up failed. Please try again."]).join(" "));

      // A brand-new account has nothing to merge: whatever this device held
      // belonged to someone else.
      await clearData();
      await writeDataKey(await lockDataKey(dataKey));
      await writeAccountStamp(data.account);

      this.element.hidden = true;
      document.dispatchEvent(new CustomEvent("recovery-code:show", { detail: { code: recoveryCode, next: "/" } }));
    } catch (e) {
      console.error("Signup failed:", e);
      this.fail("Sign up failed. Please try again.");
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
    this.submitTarget.value = "Sign Up";
  }

  fail(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }
}
