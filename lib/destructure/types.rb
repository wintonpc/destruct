require 'singleton'

class Dmatch

  class Var
    attr_reader :name

    def initialize(name=nil, &pred)
      @name = name
      @pred = pred
    end

    def test(x)
      @pred == nil ? true : @pred.call(x)
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
    attr_reader :fields

    def initialize(fields={}, &pred)
      @fields = fields
      @pred = pred
    end

    def self.of_type(klass, fields={}, &pred)
      Obj.new(fields) {|x| x.is_a?(klass) && (!pred || pred.call(x))}
    end

    def test(x)
      @pred == nil ? true : @pred.call(x)
    end
  end

  class Pred
    def initialize(pred_callable=nil, &pred_block)
      raise 'Cannot specify both a callable and a block' if pred_callable && pred_block
      @pred = pred_callable || pred_block
    end

    def test(x)
      @pred.call(x)
    end
  end

end