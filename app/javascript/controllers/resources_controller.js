import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["feed"];

  connect() {
    this.loadFeed();
  }

  async loadFeed() {
    this.feedTarget.innerHTML = '<div class="tip">Loading resources...</div>';

    try {
      const response = await fetch("https://crossroadcounselor.com/feed/", {
        mode: "no-cors"
      });
      this.feedTarget.innerHTML = '<div class="tip">Resources loaded from external site.</div>';
    } catch (e) {
      this.feedTarget.innerHTML = `
        <div class="card">
          <h3>Recommended Resources</h3>
          <ul style="margin-left:16px;font-size:13px;margin-top:8px;">
            <li><a href="https://crossroadcounselor.com/" target="_blank">Crossroads Counseling Website</a></li>
            <li><a href="https://www.therapyportal.com/p/crossroadspc/" target="_blank">Schedule an Appointment</a></li>
          </ul>
        </div>
      `;
    }
  }
}
