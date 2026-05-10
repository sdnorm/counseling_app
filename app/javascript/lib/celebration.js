export function triggerConfetti() {
  if (typeof window.confetti === "function") {
    window.confetti({
      particleCount: 100,
      spread: 70,
      origin: { y: 0.6 },
      colors: ["#32b1c3", "#f06623", "#583c25", "#a67245"],
    });
  }
}

const AFFIRMATIONS = [
  "Yay! You did it!",
  "Little by little, you're improving every day.",
  "It works if you work it.",
  "Great job showing up for yourself.",
  "Every step counts. Keep going!",
  "You're building a powerful habit.",
  "Small progress is still progress.",
];

export function showAffirmation() {
  const msg = AFFIRMATIONS[Math.floor(Math.random() * AFFIRMATIONS.length)];
  const el = document.getElementById("flash-container");
  if (el) {
    el.innerHTML = `<div class="flash">${msg}</div>`;
    setTimeout(() => { el.innerHTML = ""; }, 2500);
  }
}
