require "test_helper"

# The encrypted-blob sync pipeline is held together by a DOM event contract:
# screen controllers that write to IndexedDB must dispatch "sync:save", and
# sync_controller uploads on exactly that event name. Stimulus's dispatch()
# silently prefixes event names with the controller identifier unless
# `prefix: false` is passed, which once broke sync app-wide — this test pins
# the contract statically since there is no JS test harness.
class ClientSyncContractTest < ActiveSupport::TestCase
  CONTROLLERS_DIR = Rails.root.join("app/javascript/controllers")

  test "sync controller listens for the bare sync:save event" do
    sync = CONTROLLERS_DIR.join("sync_controller.js").read
    assert_match 'addEventListener("sync:save"', sync,
      "sync_controller.js must listen for the unprefixed sync:save event"
  end

  test "every controller that writes to lib/db dispatches an unprefixed sync:save" do
    writers = CONTROLLERS_DIR.glob("*_controller.js").select do |path|
      next false if path.basename.to_s == "sync_controller.js"
      import = path.read[/import \{([^}]*)\} from "lib\/db"/, 1]
      import && import.match?(/\b(put|remove)\b/)
    end

    assert_not_empty writers, "expected at least one controller writing to lib/db"

    writers.each do |path|
      source = path.read
      dispatches = source.scan(/dispatch\("sync:save",\s*\{([^}]*)\}/)

      assert_not_empty dispatches,
        "#{path.basename} writes to lib/db but never dispatches sync:save — its data will never reach the server"

      dispatches.each do |(options)|
        assert_includes options, "prefix: false",
          "#{path.basename} dispatches sync:save without `prefix: false` — Stimulus will " \
          "emit a controller-prefixed event name that sync_controller never receives"
      end
    end
  end
end
