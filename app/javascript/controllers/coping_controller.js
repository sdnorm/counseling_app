import { Controller } from "@hotwired/stimulus";
import { put, getAll, remove } from "lib/db";
import { escapeHtml } from "lib/html";

const DEFAULT_SKILLS = [
  "Deep breathing / box breathing",
  "Grounding (5-4-3-2-1 senses)",
  "Go for a walk",
  "Call or text a safe person",
  "Journal your thoughts",
  "Listen to calming music",
  "Progressive muscle relaxation",
  "Prayer or meditation",
  "Name your emotions out loud",
  "Watch something comforting",
  "Stretch or gentle movement",
  "Make a cup of tea",
  "Create something (draw, write, cook)",
  "Sit outside in nature",
  "Read something uplifting",
  "Get under a weighted blanket",
  "Find something soft or textured to touch",
  "Take a bath or shower",
];

export default class extends Controller {
  static targets = ["skills", "newSkill"];

  async connect() {
    const existing = await getAll("copingSkills");
    if (existing.length === 0) {
      for (const skill of DEFAULT_SKILLS) {
        await put("copingSkills", { text: skill, starred: false, custom: false });
      }
    }
    this.loadSkills();
  }

  async loadSkills() {
    const skills = await getAll("copingSkills");
    const starred = skills.filter(s => s.starred);
    const rest = skills.filter(s => !s.starred);

    this.skillsTarget.innerHTML = [
      ...starred.map(s => this.skillRow(s, true)),
      ...rest.map(s => this.skillRow(s, false)),
    ].join("");
  }

  skillRow(skill, isStarred) {
    return `
      <div style="display:flex;justify-content:space-between;align-items:center;padding:6px 0;border-bottom:1px solid var(--light-blue);">
        <span>${escapeHtml(skill.text)}</span>
        <button class="btn btn-o" style="padding:4px 8px;font-size:11px;" data-action="click->coping#toggleStar" data-text="${escapeHtml(skill.text)}">${isStarred ? "★" : "☆"}</button>
      </div>
    `;
  }

  async toggleStar(event) {
    const text = event.currentTarget.dataset.text;
    const skills = await getAll("copingSkills");
    const skill = skills.find(s => s.text === text);
    if (skill) {
      skill.starred = !skill.starred;
      await put("copingSkills", skill);
      this.loadSkills();
    }
  }

  async add() {
    const text = this.newSkillTarget.value.trim();
    if (!text) return;

    await put("copingSkills", { text, starred: false, custom: true });
    this.newSkillTarget.value = "";
    this.loadSkills();
  }
}
