# The deployed commit, shown on the Settings screen so a client can tell us
# which build they are running (a stale PWA cache once hid a shipped fix).
#
# Hatchbox writes Capistrano-style releases with a REVISION file at the app
# root. Locally there is no such file, so fall back to git; in CI or an
# unpacked tarball there is neither, and "unknown" is shown.
Rails.application.config.app_revision = begin
  revision_file = Rails.root.join("REVISION")
  sha =
    if revision_file.exist?
      revision_file.read
    elsif Rails.root.join(".git").exist?
      `git -C #{Rails.root.to_s.shellescape} rev-parse HEAD 2>/dev/null`
    end
  sha = sha.to_s.strip
  sha.match?(/\A\h{7,40}\z/) ? sha.first(7) : "unknown"
end
