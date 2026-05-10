const CACHE_NAME = "crossroads-v1";
const STATIC_ASSETS = [
  "/",
  "/assets/application.css",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener("fetch", (event) => {
  event.respondWith(
    caches.match(event.request).then((cached) => {
      return cached || fetch(event.request);
    })
  );
});

self.addEventListener("push", (event) => {
  const data = event.data?.json() || {};
  event.waitUntil(
    self.registration.showNotification(data.title || "Crossroads", {
      body: data.body || "Time for your gratitude practice!",
      icon: "/icon.png",
      badge: "/icon.png",
    })
  );
});
