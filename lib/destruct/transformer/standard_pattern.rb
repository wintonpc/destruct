# frozen_string_literal: true

require_relative './pattern_base'

class Destruct
  class Transformer
    StandardPattern = Transformer.from(PatternBase)
  end
end