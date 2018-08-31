# frozen_string_literal: true

require 'rspec/expectations'
require 'destructure'

# experimental
RSpec::Matchers.define :dmatch do |pattern|
  match do |actual|
    pattern or raise "No pattern specified"
    if pattern.is_a?(Proc)
      pattern = DMatch::SexpTransformer.transform(pattern)
    end
    !!DMatch.match(pattern, actual)
  end

  pretty_inspect = proc do |x|
    if x.is_a?(Array)
      x.map(&pretty_inspect)
    else
      x.respond_to?(:pretty_inspect) ? x.pretty_inspect : x.inspect
    end
  end


  failure_message do |actual|
    pat, x = DMatch.last_match_attempt(pattern, actual)
    "DMatch failed. Last match attempt: \n    pattern: #{pretty_inspect.(pat)}\n    object:  #{pretty_inspect.(x)}"
  end
end
