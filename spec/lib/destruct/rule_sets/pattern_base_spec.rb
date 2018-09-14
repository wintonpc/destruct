require 'destruct'
require_relative '../transformer_helpers'

class Destruct
  module PatternBaseSpecs
    Foo = Struct.new(:a, :b)
    describe RuleSets::PatternBase do
      it 'builds on Ruby to transform VarRefs and ConstRefs' do
        tx = RuleSets::PatternBase.method(:transform)
        x_var = tx.call { x }
        expect(x_var).to be_a Var
        expect(x_var.name).to eql :x

        x_const = tx.call { Foo }
        expect(x_const).to eql Foo
      end
    end
  end
end
