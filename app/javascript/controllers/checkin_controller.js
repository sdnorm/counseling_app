import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "lib/db";
import { triggerConfetti, showAffirmation } from "lib/celebration";

export default class extends Controller {
  static targets = ["score", "mode", "entries"];

  connect() {
    this.loadEntries();
  }

  async save() {
    const entry = {
      id: crypto.randomUUID(),
      date: new Date().toISOString(),
      score: parseInt(this.scoreTarget.value),
      mode: this.modeTarget.value,
    };

    await put("checkinEntries", entry);
    this.loadEntries();
    triggerConfetti();
    showAffirmation();
    this.dispatch("sync:save", { target: document.body });
  }

  async loadEntries() {
    const entries = await getAll("checkinEntries");
    entries.sort((a, b) => new Date(b.date) - new Date(a.date));

    this.entriesTarget.innerHTML = entries.slice(0, 10).map(e => `
      <div class="card">
        <div style="font-size:11px;color:var(--lt-brown);margin-bottom:4px;">${new Date(e.date).toLocaleDateString()}</div>
        <div>Score: ${e.score}/10 (${e.mode})</div>
      </div>
    `).join("");
  }
}
