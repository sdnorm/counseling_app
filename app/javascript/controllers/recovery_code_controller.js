// app/javascript/controllers/recovery_code_controller.js
import { Controller } from "@hotwired/stimulus";

// Reveals the "save your recovery code" panel. A controller that just made a
// code dispatches `recovery-code:show` with { code, next }. `next` is where
// "I've saved it" goes; null means just hide the panel again (settings).
export default class extends Controller {
  static targets = ["code"];

  connect() {
    this.handler = (event) => this.show(event.detail);
    document.addEventListener("recovery-code:show", this.handler);
  }

  disconnect() {
    document.removeEventListener("recovery-code:show", this.handler);
  }

  show({ code, next }) {
    this.next = next;
    this.codeTarget.value = code;
    this.element.hidden = false;
    this.element.scrollIntoView();
  }

  done() {
    this.codeTarget.value = "";
    if (this.next) {
      window.location.assign(this.next);
    } else {
      this.element.hidden = true;
    }
  }
}
