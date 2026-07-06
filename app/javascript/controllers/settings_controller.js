import { Controller } from "@hotwired/stimulus";
import { put, getAll } from "lib/db";

export default class extends Controller {
  static targets = ["name", "reminderTime", "haptics", "confetti"];

  async connect() {
    const settings = await getAll("settings");
    const profile = await getAll("profile");
    const name = profile.find(p => p.id === "name");

    if (name) this.nameTarget.value = name.value || "";

    const remind = settings.find(s => s.id === "reminderTime");
    if (remind) this.reminderTimeTarget.value = remind.value || "09:00";

    const haptics = settings.find(s => s.id === "haptics");
    this.hapticsTarget.checked = haptics ? haptics.value : true;

    const confetti = settings.find(s => s.id === "confetti");
    this.confettiTarget.checked = confetti ? confetti.value : true;
  }

  async save() {
    await put("profile", { id: "name", value: this.nameTarget.value.trim() });
    await put("settings", { id: "reminderTime", value: this.reminderTimeTarget.value });
    await put("settings", { id: "haptics", value: this.hapticsTarget.checked });
    await put("settings", { id: "confetti", value: this.confettiTarget.checked });

    try {
      const response = await fetch("/api/push/preferences", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
        },
        body: JSON.stringify({
          reminder_time: this.reminderTimeTarget.value,
          time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }),
      });
      if (!response.ok) console.error("Reminder preferences not saved:", response.status);
    } catch (error) {
      console.error("Reminder preferences not synced:", error);
    }

    const el = document.getElementById("flash-container");
    if (el) {
      el.innerHTML = '<div class="flash">Settings saved!</div>';
      setTimeout(() => el.innerHTML = "", 2200);
    }
  }
}
