import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "lib/db";
import { triggerConfetti, showAffirmation } from "lib/celebration";

export default class extends Controller {
  static targets = ["god", "self", "others", "snaps"];

  connect() {
    this.loadSnaps();
  }

  async save() {
    const entry = {
      id: crypto.randomUUID(),
      date: new Date().toISOString(),
      god: parseInt(this.godTarget.value),
      self: parseInt(this.selfTarget.value),
      others: parseInt(this.othersTarget.value),
    };

    await put("triangleSnaps", entry);
    this.loadSnaps();
    triggerConfetti();
    showAffirmation();
    this.dispatch("sync:save", { target: document.body });
  }

  async loadSnaps() {
    const entries = await getAll("triangleSnaps");
    entries.sort((a, b) => new Date(b.date) - new Date(a.date));

    this.snapsTarget.innerHTML = entries.slice(0, 10).map(e => `
      <div class="card">
        <div style="font-size:11px;color:var(--lt-brown);margin-bottom:4px;">${new Date(e.date).toLocaleDateString()}</div>
        <div style="display:flex;gap:8px;font-size:12px;">
          <span>God: ${e.god}</span>
          <span>Self: ${e.self}</span>
          <span>Others: ${e.others}</span>
        </div>
      </div>
    `).join("");
  }
}
