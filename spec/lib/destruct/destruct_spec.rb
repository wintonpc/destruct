# frozen_string_literal: true

require 'destruct'

class Destruct
  describe Destruct do
    Outer = Struct.new(:o)
    it 'test' do
      c = 42 # referenced lvar
      @d = 43 # referenced ivar
      w = nil # shadowed lvar
      r = destruct([1, 4, 5, 3]) do
        case
        when [v, w, u, 2]
          [v, w, u, 2, c, @d, a(@d), b, Outer.new(45)].inspect
        when [v, w, u, 3]
          [v, w, u, 3, c, @d, a(@d), b, Outer.new(45)].inspect
        else
          99.to_s
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

    FBar = Struct.new(:a, :b)
    it 'with custom transformer' do
      t = Class.new do
        include RuleSet

        def initialize
          add_rule(->{ ~v }, v: Var) { |v:| Splat.new(v.name) }
          add_rule(->{ klass[*field_pats] }, klass: [Class, Module], field_pats: [Var]) do |klass:, field_pats:|
            Obj.new(klass, field_pats.map { |f| [f.name, f] }.to_h)
          end
          add_rule_set(RuleSets::PatternBase)
        end

        def validate(x)
          RuleSets::PatternValidator.validate(x)
        end
      end

      inputs = [
          FBar.new(5, 6),
          [1, 2, 3],
          [7, 8]
      ]

      outputs = inputs.map do |inp|
        destruct(inp, t) do
          case x
          when FBar[a, b]
            [a, b]
          when [1, ~rest]
            rest
          else
            x
          end
        end
      end

      expect(outputs).to eql [[5, 6], [2, 3], [7, 8]]
    end

    it 'multiple preds per when' do
      inputs = [
          FBar.new(:first, [1, 0]),
          FBar.new(:second, [0, 2])
      ]
      outputs = inputs.map do |input|
        destruct(input) do
          case
          when FBar[a: :first, b: [v, _]], FBar[a: :second, b: [_, v]]
            v
          end
        end
      end
      expect(outputs).to eql [1, 2]
    end
  end
end
