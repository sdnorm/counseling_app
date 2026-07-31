import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "lib/db";
import { escapeHtml } from "lib/html";
import { triggerConfetti, showAffirmation } from "lib/celebration";

export default class extends Controller {
  static targets = ["score", "mode", "entries", "chart", "chartCard"];

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
    this.dispatch("sync:save", { target: document.body, prefix: false });
  }

  async loadEntries() {
    const entries = await getAll("checkinEntries");
    entries.sort((a, b) => new Date(b.date) - new Date(a.date));

    this.entriesTarget.innerHTML = entries.slice(0, 10).map(e => `
      <div class="card">
        <div style="font-size:11px;color:var(--lt-brown);margin-bottom:4px;">${new Date(e.date).toLocaleDateString()}</div>
        <div>Score: ${escapeHtml(e.score)}/10 (${escapeHtml(e.mode)})</div>
      </div>
    `).join("");

    this.drawChart(entries);
  }

  drawChart(entries) {
    if (entries.length < 2) {
      this.chartCardTarget.style.display = "none";
      return;
    }
    this.chartCardTarget.style.display = "block";

    const recent = entries.slice(0, 14).reverse(); // oldest → newest
    const w = 320, h = 120, padX = 10, padY = 10;
    const stepX = (w - padX * 2) / (recent.length - 1);
    const y = score => h - padY - ((score - 1) / 9) * (h - padY * 2);

    const points = recent.map((e, i) => ({
      x: padX + i * stepX,
      y: y(e.score),
      color: e.mode === "pre" ? "var(--blue)" : "var(--orange)",
    }));

    this.chartTarget.innerHTML = `
      <svg width="100%" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet">
        <line x1="${padX}" y1="${y(10)}" x2="${w - padX}" y2="${y(10)}" stroke="var(--light-blue)" stroke-width="1"/>
        <line x1="${padX}" y1="${y(5.5)}" x2="${w - padX}" y2="${y(5.5)}" stroke="var(--light-blue)" stroke-width="1"/>
        <line x1="${padX}" y1="${y(1)}" x2="${w - padX}" y2="${y(1)}" stroke="var(--light-blue)" stroke-width="1"/>
        <polyline points="${points.map(p => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(" ")}" fill="none" stroke="var(--deep)" stroke-width="2"/>
        ${points.map(p => `<circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="4" fill="${p.color}"/>`).join("")}
      </svg>
    `;
  }
}
