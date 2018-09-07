# frozen_string_literal: true

require 'destruct'

class Destruct
  describe Transformer do
    it 'built-in rules' do
      t = Transformer::Basic
      expect(t.transform { 1 }).to eql 1
      expect(t.transform { 2.0 }).to eql 2.0
      expect(t.transform { :x }).to eql :x
      expect(t.transform { 'x' }).to eql 'x'
      x_var = t.transform { x }
      expect(x_var).to be_a Var
      expect(x_var.name).to eql :x
    end
    it 'passes matches to the block' do
      t = Transformer.from(Transformer::Basic) do
        add_rule(->{ ~v }) do |v:|
          Splat.new(v.name)
        end
      end
      foo_splat = t.transform { ~foo }
      expect(foo_splat).to be_a Splat
      expect(foo_splat.name).to eql :foo
    end
    it 'allows matched vars to be locals' do
      t = Transformer.from(Transformer::Basic) do
        v = nil
        add_rule(->{ ~v }) do |v:|
          Splat.new(v.name)
        end
      end
      foo_splat = t.transform { ~foo }
      expect(foo_splat).to be_a Splat
      expect(foo_splat.name).to eql :foo
    end
    it 'translates more complex rules' do
      t = Transformer.from(Transformer::Basic) do
        v = nil
        add_rule(->{ ~v }) do |v:|
          Splat.new(v.name)
        end
      end
      r = t.transform { [1, ~foo] }
      expect(r[1]).to be_a Splat
      expect(r[1].name).to eql :foo
    end
    it 'translates stuff with hashes' do
      t = Transformer.from(Transformer::Basic) do
        v = nil
        add_rule(->{ ~v }) do |v:|
          Splat.new(v.name)
        end
      end
      r = t.transform { {a: 1, b: [1, ~foo]} }
      expect(r).to be_a Hash
      expect(r[:b].last).to be_a Splat
    end
    it 'metacircularish' do
      t = Transformer.from(Transformer::Basic) do
        add_rule(->{ n(type, children) }) do |type:, children:|
          Obj.new(Parser::AST::Node, type: type, children: children)
        end
      end
      pat = t.transform { n(:send, [nil, var_name]) }
      cp = Compiler.compile(pat)
      x = ExprCache.get(->{ asdf })
      e = cp.match(x)
      expect(e.var_name).to eql :asdf
    end
    # Foo = Struct.new(:a, :b)
    # it 'test' do
    #   t = tuage.from(tuage::Basic)
    #   t.add_rule(->{ n(type, children) }) do |type:, children:|
    #     Obj.new(Parser::AST::Node, type: type, children: children)
    #   end
    #   t.add_rule(->{ Class[*fields] }) do |klass:, fields:|
    #     to_s
    #   end
    #   t.translate { Foo[b, c] }
    #   to_s
    # end
  end
end
