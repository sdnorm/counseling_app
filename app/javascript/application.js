// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { jsPDF } from "jspdf";
import confetti from "canvas-confetti";

window.jsPDF = jsPDF;
window.confetti = confetti;

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js');
}
