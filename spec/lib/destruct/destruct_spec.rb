# frozen_string_literal: true

require 'destruct'

class Destruct
  describe Destruct do
    Outer = Struct.new(:o)
    it 'test' do
      outer = 42
      @outer = 43
      w = nil
      r = Destruct.destruct([1, 4, 3]) do
        case
        when [v, w, 2]
          [v, w, 2, outer, @outer, outer_method(@outer), Outer.new(45)].inspect
        when [v, w, 3]
          [v, w, 3, outer, @outer, outer_method(@outer), Outer.new(45)].inspect
        else
          99
        end
      end
      expect(r).to eql [1, 4, 3, 42, 43, 44, Outer.new(45)].inspect
      # lambda do |obj, binding|
      #   # injected params
      #   cp1 = Compiler.compile(Transformer::PatternBase.transform { [v, 2] })
      #   cp2 = Compiler.compile(Transformer::PatternBase.transform { [v, 3] })
      #
      #   # generated code
      #   if e = cp1.match(obj)
      #     [e.v, 2, binding.eval("outer")].inspect
      #   elsif e = cp2.match(obj)
      #     [e.v, 3, binding.eval("outer")].inspect
      #   else
      #     99
      #   end
      # end
    end

    def outer_method(v)
      v + 1
    end
  end
end