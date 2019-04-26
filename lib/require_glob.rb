# frozen_string_literal: true

module Kernel
  # This standardizes the way we require globs of files.
  # It also gives the dependency checker in jenkins-scripts a symbol to grep for.
  def require_glob(relative_path_glob)
    dir = File.dirname(caller[0].split(':')[0])
    Dir[File.join(dir, relative_path_glob)].sort.each { |file| require file }
  end
end
