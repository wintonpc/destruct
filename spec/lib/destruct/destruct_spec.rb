# frozen_string_literal: true

require 'destruct'
require 'colorize'

Pair = Struct.new(:h, :t)

class MatchIt
  def go
    destruct([1, :z]) do
      case
      when [a, 2, _, ~rest]
        "matched array: a = #{a}, rest = #{rest}"
      when Pair[h: "start" | "stop", t: time]
        "matched start/stop pair: time = #{time}"
      when Pair[h: head]
        "matched other pair: #{p}, head = #{head}"
      when [greeting = /hello (?<who>\w+)/, line_num]
        "greeted #{who} (#{greeting.inspect}) on line #{line_num}"
      when [!current_state, ~rest]
        "matched current state: rest = #{rest}"
      when [1, !custom_pattern]
        "matched custom pattern"

        # when {a: x, b: y}
        #   "matched hash: x = #{x}, y = #{y}"

      else
        "didn't match"
      end
    end
  end

  def current_state
    :stopped
  end

  def custom_pattern
    Destruct::RuleSets::StandardPattern.transform { :x | :y }
  end
end

class Destruct
  describe Destruct do
    it 'test' do
      puts
      puts "RESULT: #{MatchIt.new.go}".blue
    end
  end
end
