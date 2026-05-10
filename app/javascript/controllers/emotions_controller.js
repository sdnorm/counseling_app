import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "../lib/db";
import { triggerConfetti, showAffirmation } from "../lib/celebration";

const EMOTION_CHILDREN = {
  Joy: ["Happy", "Content", "Excited", "Proud", "Optimistic"],
  Sadness: ["Lonely", "Guilty", "Hopeless", "Disappointed", "Overwhelmed"],
  Anger: ["Frustrated", "Irritated", "Hostile", "Resentful", "Jealous"],
  Fear: ["Anxious", "Scared", "Insecure", "Nervous", "Terrified"],
  Surprise: ["Shocked", "Confused", "Amazed", "Startled"],
  Disgust: ["Revolted", "Ashamed", "Disappointed", "Judgmental"],
};

export default class extends Controller {
  static targets = ["details", "log"];

  connect() {
    this.selected = new Set();
    this.loadLog();
  }

  toggle(event) {
    const emotion = event.currentTarget.dataset.emotion;
    event.currentTarget.classList.toggle("active");

    if (this.selected.has(emotion)) {
      this.selected.delete(emotion);
    } else {
      this.selected.add(emotion);
    }

    this.showChildren();
  }

  showChildren() {
    const container = this.element.querySelector("#emotion-children");
    container.innerHTML = "";

    for (const core of this.selected) {
      const children = EMOTION_CHILDREN[core] || [];
      for (const child of children) {
        const btn = document.createElement("button");
        btn.className = "btn btn-o";
        btn.textContent = child;
        btn.style.fontSize = "11px";
        btn.style.padding = "4px 8px";
        btn.dataset.child = child;
        btn.dataset.action = "click->emotions#toggleChild";
        if (this.selected.has(child)) btn.classList.add("active");
        container.appendChild(btn);
      }
    }

    this.detailsTarget.style.display = this.selected.size > 0 ? "block" : "none";
  }

  toggleChild(event) {
    const child = event.currentTarget.dataset.child;
    event.currentTarget.classList.toggle("active");

    if (this.selected.has(child)) {
      this.selected.delete(child);
    } else {
      this.selected.add(child);
    }
  }

  async save() {
    if (this.selected.size === 0) return;

    const entry = {
      id: crypto.randomUUID(),
      date: new Date().toISOString(),
      emotions: Array.from(this.selected),
    };

    await put("emotionSnapshots", entry);
    this.loadLog();
    triggerConfetti();
    showAffirmation();
    this.dispatch("sync:save", { target: document.body });

    this.selected.clear();
    this.element.querySelectorAll(".active").forEach(el => el.classList.remove("active"));
    this.detailsTarget.style.display = "none";
  }

  clear() {
    this.selected.clear();
    this.element.querySelectorAll(".active").forEach(el => el.classList.remove("active"));
    this.detailsTarget.style.display = "none";
  }

  async loadLog() {
    const entries = await getAll("emotionSnapshots");
    entries.sort((a, b) => new Date(b.date) - new Date(a.date));

    this.logTarget.innerHTML = entries.slice(0, 10).map(e => `
      <div class="card">
        <div style="font-size:11px;color:var(--lt-brown);margin-bottom:4px;">${new Date(e.date).toLocaleDateString()}</div>
        <div style="display:flex;flex-wrap:wrap;gap:4px;">
          ${e.emotions.map(em => `<span style="background:var(--light-blue);color:var(--deep);padding:2px 8px;border-radius:4px;font-size:11px;">${em}</span>`).join("")}
        </div>
      </div>
    `).join("");
  }
}
