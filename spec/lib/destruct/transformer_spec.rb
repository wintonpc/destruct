# frozen_string_literal: true

require 'destruct'
require 'time_it'

class Destruct
  describe Transformer do
    it 'Ruby' do
      t = Transformer::Ruby
      expect(t.transform { 1 }).to eql 1
      expect(t.transform { 2.0 }).to eql 2.0
      expect(t.transform { :x }).to eql :x
      expect(t.transform { 'x' }).to eql 'x'
      x_var = t.transform { x }
      expect(x_var).to be_a Transformer::VarRef
      expect(x_var.name).to eql :x
    end
    it 'Pattern' do
      t = Transformer::Pattern
      x_var = t.transform { x }
      expect(x_var).to be_a Var
      expect(x_var.name).to eql :x
    end
    it 'passes matches to the block' do
      t = Transformer.from(Transformer::Ruby) do
        add_rule(->{ ~v }) do |v:|
          Splat.new(v.name)
        end
      end
      foo_splat = t.transform { ~foo }
      expect(foo_splat).to be_a Splat
      expect(foo_splat.name).to eql :foo
    end
    it 'allows matched vars to be locals' do
      t = Transformer.from(Transformer::Ruby) do
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
      t = Transformer.from(Transformer::Ruby) do
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
      time_it("test") do
        t = Transformer.from(Transformer::Ruby) do
          v = nil
          add_rule(->{ ~v }) do |v:|
            Splat.new(v.name)
          end
        end
        r = t.transform { {a: 1, b: [1, ~foo]} }
        expect(r).to be_a Hash
        expect(r[:b].last).to be_a Splat
      end
    end
    it 'metacircularish' do
      t = Transformer.from(Transformer::Pattern) do
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
    Foo = Struct.new(:a, :b)
    it 'object matches' do
      t = Transformer.from(Transformer::Ruby) do
        add_rule(->{ klass[*fields] }) do |klass:, fields:|
          Obj.new(klass, fields)
        end
      end
      cp = Compiler.compile(t.transform { Foo[a, b] })
      e = cp.match(Foo.new(1, 2))
      expect(e.a).to eql 1
      expect(e.b).to eql 2
    end
  end
end
