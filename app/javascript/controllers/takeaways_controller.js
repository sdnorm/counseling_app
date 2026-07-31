import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "lib/db";
import { escapeHtml } from "lib/html";
import { triggerConfetti, showAffirmation } from "lib/celebration";

export default class extends Controller {
  static targets = ["insight", "great", "miss", "entries"];

  connect() {
    this.loadEntries();
  }

  async save() {
    const entry = {
      id: crypto.randomUUID(),
      date: new Date().toISOString(),
      insight: this.insightTarget.value.trim(),
      great: this.greatTarget.value.trim(),
      miss: this.missTarget.value.trim(),
    };

    if (!entry.insight && !entry.great && !entry.miss) return;

    await put("takeaways", entry);
    this.loadEntries();
    triggerConfetti();
    showAffirmation();
    this.dispatch("sync:save", { target: document.body });

    this.insightTarget.value = "";
    this.greatTarget.value = "";
    this.missTarget.value = "";
  }

  async loadEntries() {
    const entries = await getAll("takeaways");
    entries.sort((a, b) => new Date(b.date) - new Date(a.date));

    this.entriesTarget.innerHTML = entries.slice(0, 10).map(e => `
      <div class="card">
        <div style="font-size:11px;color:var(--lt-brown);margin-bottom:4px;">${new Date(e.date).toLocaleDateString()}</div>
        <div style="font-size:13px;">
          ${e.insight ? `<div><strong>Insight:</strong> ${escapeHtml(e.insight)}</div>` : ""}
          ${e.great ? `<div><strong>Great:</strong> ${escapeHtml(e.great)}</div>` : ""}
          ${e.miss ? `<div><strong>Miss:</strong> ${escapeHtml(e.miss)}</div>` : ""}
        </div>
      </div>
    `).join("");
  }
}
