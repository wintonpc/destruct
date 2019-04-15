# frozen_string_literal: true

require 'unparser'
require_relative 'rule_sets/destruct'
require_relative './code_gen'
require_relative './util'

class Destruct
  include CodeGen

  NOTHING = make_singleton("#<NOTHING>")

  def self.match(pat, x, binding=nil)
    if pat.is_a?(Proc)
      pat = RuleSets::StandardPattern.transform(binding: binding, &pat)
    end
    Compiler.compile(pat).match(x, binding)
  end
end
