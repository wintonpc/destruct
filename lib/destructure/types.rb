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
      self.pred = pred
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
      self.pred = pred
    end

    def self.of_type(klass, fields={}, &pred)
      Obj.new(fields) {|x| x.is_a?(klass) && (!pred || pred.call(x))}
    end
  end

  class Pred
    include Predicated

    def initialize(pred_callable=nil, &pred_block)
      raise 'Cannot specify both a callable and a block' if pred_callable && pred_block
      self.pred = pred_callable || pred_block
    end
  end

end