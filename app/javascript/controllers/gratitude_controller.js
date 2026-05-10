import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "../lib/db";
import { triggerConfetti, showAffirmation } from "../lib/celebration";

export default class extends Controller {
  static targets = ["item1", "item2", "item3", "streak", "certificate", "entries"];

  connect() {
    this.loadEntries();
    this.updateStreak();
  }

  async save() {
    const items = [
      this.item1Target.value.trim(),
      this.item2Target.value.trim(),
      this.item3Target.value.trim(),
    ].filter(Boolean);

    if (items.length === 0) return;

    const entry = {
      id: crypto.randomUUID(),
      date: new Date().toISOString(),
      items,
    };

    await put("gratitudeEntries", entry);
    this.loadEntries();
    this.updateStreak();
    triggerConfetti();
    showAffirmation();
    this.dispatch("sync:save", { target: document.body });

    this.item1Target.value = "";
    this.item2Target.value = "";
    this.item3Target.value = "";
  }

  async loadEntries() {
    const entries = await getAll("gratitudeEntries");
    entries.sort((a, b) => new Date(b.date) - new Date(a.date));

    this.entriesTarget.innerHTML = entries.slice(0, 7).map(e => `
      <div class="card">
        <div style="font-size:11px;color:var(--lt-brown);margin-bottom:4px;">${new Date(e.date).toLocaleDateString()}</div>
        <ul style="margin-left:16px;font-size:13px;">${e.items.map(i => `<li>${i}</li>`).join("")}</ul>
      </div>
    `).join("");
  }

  async updateStreak() {
    const entries = await getAll("gratitudeEntries");
    entries.sort((a, b) => new Date(a.date) - new Date(b.date));

    let streak = 0;
    let currentDate = new Date();
    currentDate.setHours(0, 0, 0, 0);

    const entryDates = new Set(entries.map(e => {
      const d = new Date(e.date);
      d.setHours(0, 0, 0, 0);
      return d.toISOString();
    }));

    while (entryDates.has(currentDate.toISOString())) {
      streak++;
      currentDate.setDate(currentDate.getDate() - 1);
    }

    this.streakTarget.textContent = streak;

    if (streak >= 30) {
      this.certificateTarget.style.display = "block";
    }
  }

  downloadCertificate() {
    const name = "Client";
    const doc = new jsPDF();
    doc.setFontSize(22);
    doc.text("Certificate of Completion", 105, 60, { align: "center" });
    doc.setFontSize(14);
    doc.text(`This certifies that ${name}`, 105, 90, { align: "center" });
    doc.text("has completed 30 days of gratitude journaling.", 105, 105, { align: "center" });
    doc.text(`Date: ${new Date().toLocaleDateString()}`, 105, 140, { align: "center" });
    doc.save("gratitude-certificate.pdf");
  }
}
