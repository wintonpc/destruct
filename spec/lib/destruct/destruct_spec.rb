# frozen_string_literal: true

require 'destruct'

class Destruct
  describe Destruct do
    it 'test' do
      # $show_code = true
      e = ExprCache.get(->{ x })
      outer = 42
      @outer = 43
      r = Destruct.destruct([1, 3]) do
        case
        when [v, 2]
          [v, 2, outer, @outer, outer_method(@outer)].inspect
        when [v, 3]
          [v, 3, outer, @outer, outer_method(@outer)].inspect
        else
          99
        end
      end
      expect(r).to eql [1, 3, 42, 43, 44].inspect
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
