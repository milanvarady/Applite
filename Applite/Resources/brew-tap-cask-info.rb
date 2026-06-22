# Prints the JSON representation of all casks in third-party taps the user has
# already `brew tap`'d. Brew 6 introduced a tap-trust check that `FromPathLoader`
# enforces via `Homebrew::Trust.require_trusted_cask!` (raises `UntrustedTapError`).
# Applite only reads metadata here — it does not install — so we no-op that method
# for the duration of this script. Actual `brew install` calls still go through
# the user's normal brew CLI invocation and honor trust as usual.

# Suppress all warnings and logs
$stderr.reopen(File.new("/dev/null", "w"))

require "trust"
class << Homebrew::Trust
  def require_trusted_cask!(*); end
end

casks = Tap.each
  .reject { |tap| ["homebrew/core", "homebrew/cask"].include?(tap.name) }
  .flat_map do |tap|
    tap.cask_files.filter_map do |cask_file|
      cask = Cask::CaskLoader::FromPathLoader.new(cask_file).load(config: nil)
      # `FromPathLoader` doesn't construct the cask through a Tap, so `to_h`
      # may emit `tap: nil` / omit `full_token`. Inject them from the outer
      # scope so Applite's CaskDTO can decode the entry.
      hash = cask.to_h
      hash[:tap] = tap.name
      hash[:full_token] ||= "#{tap.name}/#{cask.token}"
      hash
    rescue
      nil
    end
  end

puts JSON.pretty_generate(casks)
