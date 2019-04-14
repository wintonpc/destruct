Dir.glob(File.expand_path('./destruct/**/*.rb', __dir__)).each { |rb| require_relative(rb) }
require_relative 'destruct_ext'
