# frozen_string_literal: true

require 'destruct'

class Destruct
  describe Destruct do
    Outer = Struct.new(:o)
    it 'test' do
      c = 42 # referenced lvar
      @d = 43 # referenced ivar
      w = nil # shadowed lvar
      r = Destruct.destruct([1, 4, 5, 3]) do
        case
        when [v, w, u, 2]
          [v, w, u, 2, c, @d, a(@d), b, Outer.new(45)].inspect
        when [v, w, u, 3]
          [v, w, u, 3, c, @d, a(@d), b, Outer.new(45)].inspect
        else
          99
        end
      end
      expect(r).to eql [1, 4, 5, 3, 42, 43, 44, 46, Outer.new(45)].inspect
    end

    def a(v) # referenced method with args
      v + 1
    end

    def b # referenced method without args
      46
    end

    def u # shadowed method
      nil
    end
  end
end
