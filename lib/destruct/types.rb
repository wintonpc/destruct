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
end
