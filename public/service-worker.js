// Bumped to evict caches poisoned before /api was excluded above: activate
// deletes every cache whose name isn't this one.
const CACHE_NAME = "crossroads-v6";
const STATIC_ASSETS = ["/"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((names) => {
      return Promise.all(
        names.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name))
      );
    })
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // API and admin routes, and every non-GET, go straight to the network.
  // /api responses are per-account and change constantly: unlock reads the
  // encrypted blob and the account id from /api/sync, so answering it from the
  // cache can hand a client stale data or another account's id entirely.
  if (
    url.pathname.startsWith("/api/") ||
    url.pathname.startsWith("/admin/") ||
    event.request.method !== "GET"
  ) {
    return;
  }

  // HTML pages: network first, fallback to cache only when offline.
  if (event.request.mode === "navigate" || event.request.headers.get("Accept")?.includes("text/html")) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          // Cache only real HTML. A navigation can land on a JSON endpoint —
          // an expired session mid-fetch makes the API path the post-login
          // redirect — and caching that would poison the URL for later fetches.
          const contentType = response.headers.get("Content-Type") || "";
          if (response.ok && contentType.includes("text/html")) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  // Static assets: cache first, network fallback.
  event.respondWith(
    caches.match(event.request).then((cached) => {
      return cached || fetch(event.request);
    })
  );
});

self.addEventListener("message", (event) => {
  if (event.data?.type !== "logout") return;
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(names.map((name) => caches.delete(name))))
      .then(() => event.ports[0]?.postMessage({ ok: true }))
  );
});

self.addEventListener("push", (event) => {
  const data = event.data?.json() || {};
  event.waitUntil(
    self.registration.showNotification(data.title || "Crossroads", {
      body: data.body || "Time for your gratitude practice!",
      icon: "/icon-192.png",
      badge: "/icon-192.png",
    })
  );
});
