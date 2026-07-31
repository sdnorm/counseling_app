import { Controller } from "@hotwired/stimulus";
import { getAll } from "lib/db";

export default class extends Controller {
  static targets = ["main", "title", "nav"];
  static values = { current: String };

  connect() {
    this.currentValue = "home";
    this.userName = "";
    this.appUnlocked = false;
    // Wait for the sync controller to unlock before rendering
    document.addEventListener("app:unlocked", async () => {
      this.appUnlocked = true;
      const profile = await getAll("profile");
      this.userName = profile.find(p => p.id === "name")?.value || "";
      this.render();
    });
  }

  go(event) {
    const id = event.currentTarget.dataset.id;
    if (id === "more") return;
    this.currentValue = id;
    this.render();
  }

  toggleMore() {
    const moreMenu = document.getElementById("more-menu");
    if (moreMenu) {
      this.closeMoreMenu();
    } else {
      this.showMoreMenu();
    }
  }

  closeMoreMenu() {
    document.getElementById("more-menu")?.remove();
    if (this._outsideMenuListener) {
      document.removeEventListener("pointerdown", this._outsideMenuListener);
      this._outsideMenuListener = null;
    }
  }

  showMoreMenu() {
    const menu = document.createElement("div");
    menu.id = "more-menu";
    menu.className = "card";
    menu.style.cssText = "position:absolute;bottom:calc(70px + env(safe-area-inset-bottom));left:10px;right:10px;z-index:20;";
    menu.innerHTML = `
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">
        ${this.moreLink("journal", "📓", "My Journal")}
        ${this.moreLink("gratitude", "✦", "Gratitude")}
        ${this.moreLink("emotions", "💛", "Emotions")}
        ${this.moreLink("coping", "🛡️", "Coping Skills")}
        ${this.moreLink("triangle", "△", "Triangle")}
        ${this.moreLink("checkin", "✓", "Check-In")}
        ${this.moreLink("takeaways", "📝", "Takeaways")}
        ${this.moreLink("agenda", "📋", "Agenda")}
        ${this.moreLink("resources", "📚", "Resources")}
        ${this.moreLink("settings", "⚙️", "Settings")}
      </div>
    `;
    menu.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-id]");
      if (!btn) return;
      const id = btn.dataset.id;
      this.closeMoreMenu();
      this.currentValue = id;
      this.render();
    });
    this.element.querySelector("#app-root").appendChild(menu);

    this._outsideMenuListener = (e) => {
      if (e.target.closest("#more-menu")) return;
      if (e.target.closest('[data-id="more"]')) return;
      this.closeMoreMenu();
    };
    // Defer so the pointer event that opened the menu doesn't close it immediately.
    setTimeout(() => {
      document.addEventListener("pointerdown", this._outsideMenuListener);
    }, 0);
  }

  moreLink(id, icon, label) {
    return `<button class="nav-btn" data-id="${id}" style="border:1px solid var(--light-blue);border-radius:6px;padding:8px;">
      <span class="nav-icon">${icon}</span>
      <span class="nav-label">${label}</span>
    </button>`;
  }

  render() {
    if (!this.appUnlocked) return;
    const titles = {
      home: "CROSSROADS", schedule: "Schedule", journal: "My Journal",
      gratitude: "Gratitude Log", emotions: "Emotions", coping: "Coping Skills",
      triangle: "Triangle", checkin: "Check-In", takeaways: "Takeaways",
      agenda: "Agenda", resources: "Resources", settings: "Settings"
    };
    document.getElementById("topbar-title").textContent = titles[this.currentValue] || "CROSSROADS";

    document.querySelectorAll(".nav-btn").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.id === this.currentValue);
    });

    const main = document.getElementById("main-content");
    const renderers = {
      home: () => this.renderHome(),
      schedule: () => this.renderSchedule(),
    };

    if (renderers[this.currentValue]) {
      main.innerHTML = renderers[this.currentValue]();
    } else {
      this.loadScreen(this.currentValue);
    }
  }

  renderHome() {
    return `
      <h2>Welcome${this.userName ? `, ${this.userName}` : ""}!</h2>
      <p class="subtitle">What would you like to work on today?</p>
      <div class="card card-blue" data-action="click->navigation#go" data-id="journal">
        <strong>📓 My Journal</strong>
      </div>
      <div class="card card-orange" data-action="click->navigation#go" data-id="agenda">
        <strong>📋 Agenda</strong>
      </div>
      <div class="card card-blue" data-action="click->navigation#go" data-id="checkin">
        <strong>✓ Pre/Post Check-In</strong>
      </div>
      <div class="card card-brown" data-action="click->navigation#go" data-id="schedule">
        <strong>🗓️ Schedule</strong>
      </div>
      <div class="tip" style="margin-top:16px;">${this.legalDisclaimer()}</div>
    `;
  }

  legalDisclaimer() {
    return `Important: This app is not monitored. If you're in a mental health crisis,
      call 911 or go to your nearest ER. You may also call/text 988.
      This app is not a substitute for professional mental health care and does
      not constitute a therapeutic relationship. The content you save on this app
      is encrypted and neither the server nor any user has access to your data
      apart from your passphrase/key.`;
  }

  renderSchedule() {
    return `
      <h2>Schedule a Session</h2>
      <p class="subtitle">Choose how you'd like to book your next appointment.</p>
      <div class="card">
        <a href="https://www.therapyportal.com/p/crossroadspc/" target="_blank" class="link-btn" style="background:var(--blue)">
          🗓️ Book Online
          <small>Use our online scheduling portal</small>
        </a>
        <a href="tel:+12253414147" class="link-btn" style="background:var(--orange)">
          📞 Call Our Office
          <small>(225) 341-4147</small>
        </a>
        <a href="mailto:logan@crossroadcounselor.com" class="link-btn" style="background:var(--brown)">
          ✉️ Email Us
          <small>logan@crossroadcounselor.com</small>
        </a>
      </div>
      <div class="tip" style="margin-top:16px;">${this.legalDisclaimer()}
        This email address delivers directly to our administrative assistant and is
        for appointment requests only.</div>
    `;
  }

  async loadScreen(screen) {
    const main = document.getElementById("main-content");
    main.innerHTML = '<div class="tip">Loading...</div>';
    const response = await fetch(`/screens/${screen}`, {
      headers: { "Accept": "text/html" },
      credentials: "same-origin"
    });
    if (response.ok) {
      main.innerHTML = await response.text();
    } else {
      main.innerHTML = '<div class="tip">Could not load screen.</div>';
    }
  }
}
