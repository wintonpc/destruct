require 'destruct'
require_relative '../transformer_helpers'

class Destruct
  describe RuleSets::Ruby do
    it 'transforms ruby AST nodes to ruby objects' do
      tx = RuleSets::Ruby.method(:transform)
      # expect(tx.call { 1 }).to eql 1
      # expect(tx.call { 2.0 }).to eql 2.0
      # expect(tx.call { :x }).to eql :x
      # expect(tx.call { 'x' }).to eql 'x'
      # expect(tx.call { true }).to eql true
      # expect(tx.call { false }).to eql false
      # expect(tx.call { nil }).to eql nil
      # expect(tx.call { [1, 2] }).to eql [1, 2]
      expect(tx.call { {a: 1, b: 2} }).to eql({a: 1, b: 2})

      # x_var = tx.call { x }
      # expect(x_var).to be_a RuleSets::Ruby::VarRef
      # expect(x_var.name).to eql :x
      #
      # x_const = tx.call { TFoo }
      # expect(x_const).to be_a RuleSets::Ruby::ConstRef
      # expect(x_const.fqn).to eql 'TFoo'
      #
      # x_const = tx.call { Destruct::TFoo }
      # expect(x_const).to be_a RuleSets::Ruby::ConstRef
      # expect(x_const.fqn).to eql 'Destruct::TFoo'
      #
      # x_const = tx.call { ::Destruct::TFoo }
      # expect(x_const).to be_a RuleSets::Ruby::ConstRef
      # expect(x_const.fqn).to eql '::Destruct::TFoo'
    end
  end
end
