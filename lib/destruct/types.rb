# frozen_string_literal: true

class Destruct
  Any = Object.new

  module Binder
  end

  Var = Struct.new(:name)
  class Var
    include Binder

    def initialize(name)
      self.name = name
    end

    def inspect
      "#<Var: #{name}>"
    end
    alias_method :to_s, :inspect
  end

  Splat = Struct.new(:name)
  class Splat
    include Binder

    def initialize(name)
      self.name = name
    end

    def inspect
      "#<Splat: #{name}>"
    end
    alias_method :to_s, :inspect
  end

  Let = Struct.new(:name, :pattern)
  class Let
    include Binder

    def initialize(name, pattern)
      self.name = name
      self.pattern = pattern
    end

    def inspect
      "#<Let: #{name} = #{pattern}>"
    end
    alias_method :to_s, :inspect
  end

  Unquote = Struct.new(:code_expr)
  class Unquote
    def inspect
      "#<Unquote: #{code_expr}>"
    end
    alias_method :to_s, :inspect
  end

  Obj = Struct.new(:type, :fields)
  class Obj
    def initialize(type, fields={})
      unless type.is_a?(Class) || type.is_a?(Module)
        raise "Obj type must be a Class or a Module, was: #{type}"
      end
      self.type = type
      self.fields = fields
    end

    def inspect
      "#<Obj: #{type}[#{fields.map { |(k, v)| "#{k}: #{v}"}.join(", ")}]>"
    end
    alias_method :to_s, :inspect
  end

  Or = Struct.new(:patterns)
  class Or
    def initialize(*patterns)
      self.patterns = flatten(patterns)
    end

    def inspect
      "#<Or: #{patterns.map(&:inspect).join(", ")}>"
    end
    alias_method :to_s, :inspect

    private

    def flatten(ps)
      ps.inject([]) {|acc, p| p.is_a?(Or) ? acc + p.patterns : acc << p}
    end
  end
end
