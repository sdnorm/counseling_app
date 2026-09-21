// vendor/javascript/lib/request.js

// One JSON round trip. Never throws on HTTP errors: callers branch on
// `ok`/`status` and read `data.errors`. A non-JSON body (a redirect to an
// HTML page, say) yields `data = {}`.
export async function requestJSON(method, url, body) {
  const response = await fetch(url, {
    method,
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const data = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, data };
}
