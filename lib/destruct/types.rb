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
end
