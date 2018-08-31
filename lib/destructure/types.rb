# frozen_string_literal: true

require 'singleton'

module Predicated
  def test(x, env=nil)
    @pred == nil ? true : @pred.call(x, env)
  end

  private
  attr_accessor :pred
end

class DMatch
  class Var
    include Predicated

    attr_reader :name

    def initialize(name=nil, &pred)
      @name = name
      @pred = pred
    end

    def pretty_inspect
      "var #{name}"
    end
  end

  class Splat < Var; end

  # experimental
  class FilterSplat < Splat
    attr_reader :pattern

    def initialize(name=nil, pattern)
      super(name)
      @pattern = pattern
      validate_pattern
    end

    def validate_pattern
      raise 'FilterSplat pattern cannot contain variables' if @pattern.flatten.any?{|p| p.is_a?(Var)}
    end
  end

  # experimental
  class SelectSplat < Splat
    attr_reader :pattern

    def initialize(name=nil, pattern)
      super(name)
      @pattern = pattern
    end
  end

  class Obj
    include Predicated

    attr_reader :fields

    def initialize(fields={}, &pred)
      @fields = fields
      @pred = pred
    end

    def self.of_type(klass, fields={}, &pred)
      result = Obj.new(fields) {|x| x.is_a?(klass) && (!pred || pred.call(x))}
      result.instance_variable_set(:@type, klass)
      result
    end

    def pretty_inspect
      s = @type ? @type.to_s : "Object"
      unless @fields.empty?
        s += " with fields #{@fields.inspect}"
      end
      if @pred
        s += " matching predicate #{@pred}"
      end
      s
    end
  end

  class Pred
    include Predicated

    def initialize(pred_callable=nil, &pred_block)
      raise 'Cannot specify both a callable and a block' if pred_callable && pred_block
      @pred = pred_callable || pred_block
    end
  end

  class Or
    attr_reader :patterns

    def initialize(*patterns)
      @patterns = flatten(patterns)
    end

    private

    def flatten(ps)
      ps.inject([]) {|acc, p| p.is_a?(Or) ? acc + p.patterns : acc << p}
    end
  end
end
