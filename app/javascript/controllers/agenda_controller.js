import { Controller } from "@hotwired/stimulus";
import { put, getAll, remove } from "lib/db";
import { escapeHtml } from "lib/html";

export default class extends Controller {
  static targets = ["items"];

  connect() {
    this.loadItems();
  }

  async loadItems() {
    const items = await getAll("agendaItems");
    if (items.length === 0) {
      await put("agendaItems", { id: "default", text: "" });
    }

    this.itemsTarget.innerHTML = items.map((item, i) => `
      <div style="display:flex;gap:8px;margin-bottom:6px;">
        <span style="color:var(--orange);font-weight:700">•</span>
        <input type="text" value="${escapeHtml(item.text)}" data-index="${i}" data-action="blur->agenda#update" style="flex:1;" />
        <button class="btn btn-o" style="padding:2px 6px;font-size:11px;" data-action="click->agenda#remove" data-id="${escapeHtml(item.id)}">×</button>
      </div>
    `).join("");
  }

  async add() {
    await put("agendaItems", { id: crypto.randomUUID(), text: "" });
    this.loadItems();
  }

  async update(event) {
    const items = await getAll("agendaItems");
    const index = parseInt(event.target.dataset.index);
    if (items[index]) {
      items[index].text = event.target.value;
      await put("agendaItems", items[index]);
    }
  }

  async remove(event) {
    const id = event.currentTarget.dataset.id;
    await remove("agendaItems", id);
    this.loadItems();
  }
}
