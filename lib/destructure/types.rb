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

  SplattedEnumerable = Struct.new(:before, :splat, :after)

  class Pattern
    def self.from(p)
      p.is_a?(Pattern) ? p : Pattern.new(p)
    end

    def self.get_cooked(p)
      Pattern.from(p).pat
    end

    attr_reader :pat

    def initialize(raw_pat)
      @pat = cook(raw_pat)
    end

    private

    def cook(x)
      if x.is_a?(Array)
        cook_array(x)
      elsif x.is_a?(Hash)
        x.each_with_object({}) do |(k, v), h|
          h[k] = cook(v)
        end
      else
        x
      end
    end

    def cook_array(pat)
      before = []
      splat = nil
      after = []
      pat.each do |p|
        case
        when p.is_a?(Splat)
          if splat.nil?
            splat = p
          else
            raise "cannot have more than one splat in a single array: #{pat.inspect}"
          end
        when splat.nil?
          before.push(p)
        else
          after.push(p)
        end
      end

      if splat
        SplattedEnumerable.new(cook(before), splat, cook(after))
      else
        pat.map { |x| cook(x) }
      end
    end
  end
end
