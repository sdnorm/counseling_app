require "test_helper"

# The service worker sits in front of every GET the app makes, including the
# /api/sync call that unlock depends on. Two rules keep it from answering with
# someone else's or yesterday's data; there is no JS test harness, so pin them
# statically.
class ServiceWorkerContractTest < ActiveSupport::TestCase
  SERVICE_WORKER = Rails.root.join("public/service-worker.js")

  def source
    SERVICE_WORKER.read
  end

  def fetch_handler
    source[/addEventListener\("fetch".+?\n\}\);/m]
  end

  test "api requests bypass the service worker entirely" do
    handler = fetch_handler
    assert handler, "expected a fetch handler in service-worker.js"

    bypass = handler[/if \s*\((.+?)\)\s*\{\s*\n\s*return;/m, 1]
    assert bypass, "expected an early return that sends some requests straight to the network"

    assert_match(%r{/api/}, bypass,
      "/api/ responses are per-account and change constantly — serving a cached one " \
      "can hand a client another account's id or an out-of-date encrypted blob")
  end

  test "only html responses are written to the cache" do
    handler = fetch_handler
    put_call = handler[/caches\.open\([^)]*\)\.then\(\([^)]*\) => [a-z]+\.put\([^)]*\)\)/]
    assert put_call, "expected the navigation branch to populate the cache"

    guard_region = handler[/\.then\(\(response\) => \{(.+?)return response;/m, 1]
    assert guard_region, "expected the navigation branch to inspect the response before caching"

    assert_match(/content-type|Content-Type/i, guard_region,
      "a navigation to a JSON endpoint (reachable when a session expires mid-fetch and " \
      "the API path becomes the post-login redirect) must not poison the cache for that URL")
    assert_match(/text\/html/, guard_region,
      "only text/html responses belong in the page cache")
  end

  test "stale caches are dropped on activate" do
    activate = source[/addEventListener\("activate".+?\n\}\);/m]
    assert activate, "expected an activate handler"
    assert_match(/caches\.delete/, activate,
      "bumping CACHE_NAME must evict previously cached responses, including any " \
      "poisoned /api entries already sitting on clients")
  end
end
