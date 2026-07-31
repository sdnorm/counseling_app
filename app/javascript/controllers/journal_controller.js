import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "lib/db";
import { escapeHtml } from "lib/html";
import { triggerConfetti, showAffirmation } from "lib/celebration";

export default class extends Controller {
  static targets = ["mode", "prompt", "longInput", "bulletInput", "entries"];

  connect() {
    this.loadEntries();
  }

  toggleMode() {
    const isLong = this.modeTarget.value === "long";
    this.longInputTarget.style.display = isLong ? "block" : "none";
    this.bulletInputTarget.style.display = isLong ? "none" : "block";
  }

  addBullet() {
    const container = this.bulletInputTarget.querySelector("#bullet-container");
    const n = container.children.length + 1;
    const row = document.createElement("div");
    row.className = "ag-row";
    row.innerHTML = `<span style="color:var(--orange);font-weight:700">•</span><input type="text" placeholder="Item ${n}"/>`;
    container.appendChild(row);
  }

  async save() {
    const mode = this.modeTarget.value;
    let content = "";

    if (mode === "long") {
      content = this.longInputTarget.querySelector("textarea").value.trim();
    } else {
      const inputs = this.bulletInputTarget.querySelectorAll("input");
      content = Array.from(inputs).map(i => i.value.trim()).filter(Boolean).join("\n• ");
    }

    if (!content) return;

    const entry = {
      id: crypto.randomUUID(),
      date: new Date().toISOString(),
      mode,
      prompt: this.promptTarget.value,
      content
    };

    await put("journalEntries", entry);
    this.loadEntries();
    triggerConfetti();
    showAffirmation();
    this.dispatch("sync:save", { target: document.body });

    if (mode === "long") {
      this.longInputTarget.querySelector("textarea").value = "";
    } else {
      this.bulletInputTarget.querySelector("#bullet-container").innerHTML = `
        <div class="ag-row"><span style="color:var(--orange);font-weight:700">•</span><input type="text" placeholder="Item 1"/></div>
      `;
    }
  }

  async loadEntries() {
    const entries = await getAll("journalEntries");
    entries.sort((a, b) => new Date(b.date) - new Date(a.date));

    this.entriesTarget.innerHTML = entries.slice(0, 10).map(e => `
      <div class="card">
        <div style="font-size:11px;color:var(--lt-brown);margin-bottom:4px;">${new Date(e.date).toLocaleDateString()}</div>
        <div style="white-space:pre-wrap;font-size:13px;">${escapeHtml(e.content.substring(0, 200))}${e.content.length > 200 ? "..." : ""}</div>
      </div>
    `).join("");
  }
}
