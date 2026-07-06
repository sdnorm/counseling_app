import { Controller } from "@hotwired/stimulus";
import { getAll } from "lib/db";

export default class extends Controller {
  static targets = ["toggle", "hint"];

  async connect() {
    if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
      this.element.hidden = true;
      return;
    }

    if (Notification.permission === "denied") {
      this.showBlocked();
      return;
    }

    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription();
    this.toggleTarget.checked = !!subscription;
  }

  async toggle() {
    if (this.toggleTarget.checked) {
      try {
        await this.subscribe();
        await this.sendPreferences();
      } catch (error) {
        console.error("Push toggle failed:", error);
        this.toggleTarget.checked = false;
        if (Notification.permission === "denied") this.showBlocked();
      }
    } else {
      try {
        await this.unsubscribe();
      } catch (error) {
        console.error("Push unsubscribe failed:", error);
      }
    }
  }

  async subscribe() {
    const keyResponse = await fetch("/api/push/vapid_public_key");
    const { public_key } = await keyResponse.json();

    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.urlBase64ToUint8Array(public_key),
    });

    const response = await fetch("/api/push", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
      },
      body: JSON.stringify({
        endpoint: subscription.endpoint,
        p256dh: btoa(String.fromCharCode(...new Uint8Array(subscription.getKey("p256dh")))),
        auth: btoa(String.fromCharCode(...new Uint8Array(subscription.getKey("auth")))),
      }),
    });
    if (!response.ok) {
      await subscription.unsubscribe();
      throw new Error(`Push subscription rejected by server (${response.status})`);
    }
  }

  async unsubscribe() {
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription();
    if (subscription) {
      await subscription.unsubscribe();
      await fetch("/api/push", {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
        },
        body: JSON.stringify({ endpoint: subscription.endpoint }),
      });
    }
  }

  async sendPreferences() {
    const settings = await getAll("settings");
    const remind = settings.find((s) => s.id === "reminderTime");

    const response = await fetch("/api/push/preferences", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
      },
      body: JSON.stringify({
        reminder_time: remind?.value || "09:00",
        time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      }),
    });
    if (!response.ok) console.error("Reminder preferences not saved:", response.status);
  }

  showBlocked() {
    this.toggleTarget.checked = false;
    this.toggleTarget.disabled = true;
    this.hintTarget.hidden = false;
  }

  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/\-/g, "+").replace(/_/g, "/");
    const rawData = atob(base64);
    return Uint8Array.from([...rawData].map((char) => char.charCodeAt(0)));
  }
}
