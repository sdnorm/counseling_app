// app/javascript/controllers/brand_preview_controller.js
import { Controller } from "@hotwired/stimulus";

const HEX = /^#[0-9a-f]{6}$/i;

export default class extends Controller {
  static targets = ["name", "primary", "accent", "logo", "bar", "button", "namePreview", "logoPreview"];

  update() {
    if (this.hasNameTarget) this.namePreviewTarget.textContent = this.nameTarget.value.toUpperCase();
    if (HEX.test(this.primaryTarget.value)) this.barTarget.style.background = this.primaryTarget.value;
    if (HEX.test(this.accentTarget.value)) this.buttonTarget.style.background = this.accentTarget.value;
    const file = this.hasLogoTarget && this.logoTarget.files[0];
    if (file) {
      this.logoPreviewTarget.src = URL.createObjectURL(file);
      this.logoPreviewTarget.style.display = "";
      this.namePreviewTarget.style.display = "none";
    }
  }
}
