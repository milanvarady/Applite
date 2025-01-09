# Prints the JSON representation of all casks in thirdparty taps

# Suppress all warnings and logs
$stderr.reopen(File.new("/dev/null", "w"))

casks = Tap.each
  .reject { |tap| ["homebrew/core", "homebrew/cask"].include?(tap.name) }
  .flat_map do |tap|
    tap.cask_files.filter_map do |cask_file|
      Cask::CaskLoader::FromPathLoader.new(cask_file).load(config: nil)
    rescue
      nil
    end
  end

puts JSON.pretty_generate(casks.map(&:to_h))
