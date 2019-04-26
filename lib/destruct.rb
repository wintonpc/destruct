# frozen_string_literal: true

def require_glob(relative_path_glob)
  dir = File.dirname(caller[0].split(':')[0])
  Dir[File.join(dir, relative_path_glob)].sort.each { |file| require file }
end

require_glob 'destruct/**/*.rb'
require_relative 'destruct_ext'
