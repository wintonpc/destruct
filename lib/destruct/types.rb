# frozen_string_literal: true

class Destruct
  class Var
    attr_reader :name

    def initialize(name = nil)
      @name = name
    end

    def inspect
      "#<Var: #{name}>"
    end
  end

  class Splat < Var; end

  class Obj
    attr_reader :type, :fields

    def initialize(type, fields={})
      @type = type
      @fields = fields
    end

    def inspect
      "#<Obj: #{@type}[#{fields.map { |(k, v)| "#{k}: #{v}"}.join(", ")}]>"
    end
  end

  class Or
    attr_reader :patterns

    def initialize(*patterns)
      @patterns = flatten(patterns)
    end

    def inspect
      "#<Or: #{patterns.map(&:inspect).join(", ")}>"
    end

    private

    def flatten(ps)
      ps.inject([]) {|acc, p| p.is_a?(Or) ? acc + p.patterns : acc << p}
    end
  end
end
