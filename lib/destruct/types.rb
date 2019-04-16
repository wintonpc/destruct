# frozen_string_literal: true

require_relative './util'

class Destruct
  # Accept any value
  Any = make_singleton("#<Any>")

  module Binder
  end

  # Bind a single value
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

  # Bind zero or more values
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

  Strict = Struct.new(:pat)
  class Strict
    def inspect
      "#<Strict: #{pat}>"
    end
    alias_method :to_s, :inspect
  end

  # Bind a value but continue to match a subpattern
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

  # A subpattern supplied by a match-time expression
  Unquote = Struct.new(:code_expr)
  class Unquote
    def inspect
      "#<Unquote: #{code_expr}>"
    end
    alias_method :to_s, :inspect
  end

  # Match an object of a particular type with particular fields
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
      "#<Obj: #{type}[#{fields.map { |(k, v)| "#{k}: #{v.inspect}"}.join(", ")}]>"
    end
    alias_method :to_s, :inspect
  end

  # Bind based on the first pattern that matches
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
