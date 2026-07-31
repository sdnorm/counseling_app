import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "lib/db";
import { escapeHtml } from "lib/html";
import { triggerConfetti, showAffirmation } from "lib/celebration";

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
        <ul style="margin-left:16px;font-size:13px;">${e.items.map(i => `<li>${escapeHtml(i)}</li>`).join("")}</ul>
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

  async downloadCertificate() {
    const profile = await getAll("profile");
    const name = profile.find(p => p.id === "name")?.value || "Client";
    const certWindow = window.open("", "_blank");
    certWindow.document.write(`
      <html>
      <head><title>Gratitude Certificate</title></head>
      <body style="font-family:'Lora',serif;text-align:center;padding:60px 20px;background:#f3f8f9;">
        <div style="border:4px solid #32b1c3;padding:40px;max-width:500px;margin:0 auto;background:white;">
          <h1 style="color:#583c25;">Certificate of Completion</h1>
          <p style="font-size:18px;color:#a67245;margin-top:30px;">This certifies that</p>
          <p style="font-size:24px;color:#32b1c3;font-weight:bold;">${name}</p>
          <p style="font-size:18px;color:#a67245;">has completed 30 days of gratitude journaling.</p>
          <p style="font-size:14px;color:#583c25;margin-top:40px;">${new Date().toLocaleDateString()}</p>
        </div>
        <script>window.print();</script>
      </body>
      </html>
    `);
    certWindow.document.close();
  }
}
