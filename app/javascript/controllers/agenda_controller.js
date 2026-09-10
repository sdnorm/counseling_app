import { Controller } from "@hotwired/stimulus";
import { put, getAll, remove } from "lib/db";
import { escapeHtml } from "lib/html";

const NEXT_SESSION_ID = "nextSession";

export default class extends Controller {
  static targets = ["items", "nextSession", "nextSessionLabel"];

  connect() {
    this.loadItems();
  }

  async loadItems() {
    const records = await getAll("agendaItems");
    const nextSession = records.find((record) => record.id === NEXT_SESSION_ID);
    const items = records.filter((record) => record.id !== NEXT_SESSION_ID);

    if (items.length === 0) {
      const placeholder = { id: "default", text: "", createdAt: new Date().toISOString() };
      await put("agendaItems", placeholder);
      items.push(placeholder);
    }

    items.sort((a, b) => {
      if (!a.createdAt && !b.createdAt) return 0;
      if (!a.createdAt) return -1;
      if (!b.createdAt) return 1;
      if (a.createdAt < b.createdAt) return -1;
      if (a.createdAt > b.createdAt) return 1;
      return 0;
    });

    this.showNextSession(nextSession?.date);

    const open = items.filter((item) => !item.discussed);
    const discussed = items.filter((item) => item.discussed);

    this.itemsTarget.innerHTML = `
      ${open.map((item) => this.itemRow(item)).join("")}
      ${discussed.length === 0 ? "" : `
        <details class="agenda-discussed">
          <summary>Discussed (${discussed.length})</summary>
          ${discussed.map((item) => this.itemRow(item)).join("")}
        </details>
      `}
    `;
  }

  async add() {
    await put("agendaItems", {
      id: crypto.randomUUID(),
      text: "",
      createdAt: new Date().toISOString(),
      discussed: false,
    });
    this.dispatch("sync:save", { target: document.body, prefix: false });
    this.loadItems();
  }

  async update(event) {
    const item = await this.findItem(event.target.dataset.id);
    if (!item) return;
    item.text = event.target.value;
    await put("agendaItems", item);
    this.dispatch("sync:save", { target: document.body, prefix: false });
  }

  async toggleDiscussed(event) {
    const item = await this.findItem(event.target.dataset.id);
    if (!item) return;
    item.discussed = event.target.checked;
    await put("agendaItems", item);
    this.dispatch("sync:save", { target: document.body, prefix: false });
    this.loadItems();
  }

  async remove(event) {
    const id = event.currentTarget.dataset.id;
    if (!id || id === NEXT_SESSION_ID) return;
    await remove("agendaItems", id);
    this.dispatch("sync:save", { target: document.body, prefix: false });
    this.loadItems();
  }

  async saveNextSession() {
    const date = this.nextSessionTarget.value;
    if (date) {
      await put("agendaItems", { id: NEXT_SESSION_ID, date });
    } else {
      await remove("agendaItems", NEXT_SESSION_ID);
    }
    this.dispatch("sync:save", { target: document.body, prefix: false });
    this.showNextSession(date);
  }

  async findItem(id) {
    if (!id || id === NEXT_SESSION_ID) return null;
    const records = await getAll("agendaItems");
    return records.find((record) => record.id === id) || null;
  }

  showNextSession(date) {
    if (this.hasNextSessionTarget) this.nextSessionTarget.value = date || "";
    if (!this.hasNextSessionLabelTarget) return;
    const text = this.formatNextSession(date);
    this.nextSessionLabelTarget.textContent = text;
    this.nextSessionLabelTarget.hidden = !text;
  }

  formatNextSession(date) {
    if (!date) return "";
    const parts = date.split("-").map(Number);
    if (parts.length !== 3 || parts.some((n) => !Number.isFinite(n))) return "";
    const [year, month, day] = parts;
    const dt = new Date(year, month - 1, day);
    if (Number.isNaN(dt.getTime())) return "";
    const formatted = dt.toLocaleDateString("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
    });
    return `Next session: ${formatted}`;
  }

  itemRow(item) {
    const id = escapeHtml(item.id);
    const checked = item.discussed ? "checked" : "";
    return `
      <div class="agenda-row">
        <input type="text" value="${escapeHtml(item.text)}" data-id="${id}" data-action="blur->agenda#update" />
        <label class="agenda-check">
          <input type="checkbox" ${checked} data-id="${id}" data-action="change->agenda#toggleDiscussed" />
          Discussed
        </label>
        <button class="btn btn-o" style="padding:2px 6px;font-size:11px;" data-action="click->agenda#remove" data-id="${id}">×</button>
      </div>
    `;
  }
}
