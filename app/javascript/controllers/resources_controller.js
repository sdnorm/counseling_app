import { Controller } from "@hotwired/stimulus";
import { escapeHtml } from "lib/html";

const GENERIC_RESOURCES = [
  {
    title: "Nothing here yet",
    url: "/",
    description: "Your counselor hasn't added any links. Ask them what they'd like you to have here."
  }
];

function practiceContent() {
  try {
    return JSON.parse(document.getElementById("practice-content")?.textContent || "{}");
  } catch {
    return {};
  }
}

export default class extends Controller {
  static targets = ["feed"];

  connect() {
    this.loadFeed();
  }

  loadFeed() {
    const resources = practiceContent().resources || [];
    const list = resources.length ? resources : GENERIC_RESOURCES;
    this.feedTarget.innerHTML = list.map(resource => `
      <div class="card">
        <h3><a href="${escapeHtml(resource.url)}" target="_blank" rel="noopener">${escapeHtml(resource.title)}</a></h3>
        ${resource.description ? `<p style="font-size:13px;margin-top:8px;">${escapeHtml(resource.description)}</p>` : ""}
      </div>
    `).join("");
  }
}
