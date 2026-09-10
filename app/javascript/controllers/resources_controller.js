import { Controller } from "@hotwired/stimulus";
import { escapeHtml } from "lib/html";

const RESOURCES = [
  {
    title: "Crossroads Counseling Website",
    url: "https://crossroadcounselor.com/",
    description: "Learn about Crossroads Counseling and the services available."
  },
  {
    title: "Schedule an Appointment",
    url: "https://www.therapyportal.com/p/crossroadspc/",
    description: "Visit the client portal to schedule a counseling appointment."
  }
];

export default class extends Controller {
  static targets = ["feed"];

  connect() {
    this.loadFeed();
  }

  loadFeed() {
    this.feedTarget.innerHTML = RESOURCES.map(resource => `
      <div class="card">
        <h3><a href="${escapeHtml(resource.url)}" target="_blank" rel="noopener">${escapeHtml(resource.title)}</a></h3>
        <p style="font-size:13px;margin-top:8px;">${escapeHtml(resource.description)}</p>
      </div>
    `).join("");
  }
}
