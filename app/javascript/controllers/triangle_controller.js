import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "lib/db";
import { triggerConfetti, showAffirmation } from "lib/celebration";

export default class extends Controller {
  static targets = ["god", "self", "others", "snaps", "chart"];

  connect() {
    this.loadSnaps();
    this.draw();
  }

  draw() {
    this.chartTarget.innerHTML = this.triangleSvg(
      parseInt(this.godTarget.value),
      parseInt(this.selfTarget.value),
      parseInt(this.othersTarget.value),
      180
    );
  }

  // Radar-style triangle: each value plots a vertex along its own spoke
  // (God = top, Self = bottom-left, Others = bottom-right).
  triangleSvg(god, self, others, size) {
    const cx = size / 2, cy = size / 2 + 8, r = size / 2 - 14;
    const angles = [-90, 150, 30]; // degrees: God, Self, Others
    const point = (angle, scale) => {
      const rad = (angle * Math.PI) / 180;
      return `${(cx + r * scale * Math.cos(rad)).toFixed(1)},${(cy + r * scale * Math.sin(rad)).toFixed(1)}`;
    };
    const outer = angles.map(a => point(a, 1)).join(" ");
    const inner = angles.map((a, i) => point(a, [god, self, others][i] / 10)).join(" ");
    const labels = [
      { a: -90, text: `God ${god}`, dy: -6 },
      { a: 150, text: `Self ${self}`, dy: 12 },
      { a: 30, text: `Others ${others}`, dy: 12 },
    ].map(l => {
      const rad = (l.a * Math.PI) / 180;
      const x = cx + (r + 2) * Math.cos(rad);
      const y = cy + (r + 2) * Math.sin(rad) + l.dy;
      return `<text x="${x.toFixed(1)}" y="${y.toFixed(1)}" text-anchor="middle" font-size="10" fill="var(--brown)" font-weight="600">${l.text}</text>`;
    }).join("");

    return `
      <svg width="${size}" height="${size + 10}" viewBox="0 0 ${size} ${size + 10}">
        <polygon points="${outer}" fill="none" stroke="var(--light-blue)" stroke-width="1.5"/>
        <polygon points="${inner}" fill="rgba(50,177,195,0.25)" stroke="var(--blue)" stroke-width="2"/>
        ${labels}
      </svg>
    `;
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
