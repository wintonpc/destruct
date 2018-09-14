# frozen_string_literal: true

require 'destruct'
require 'time_it'
require_relative './transformer_helpers'

class Destruct
  describe Transformer do
    include TransformerHelpers

    TFoo = Struct.new(:a, :b)
    it 'passes matches to the block' do
      given_pattern { [1, ~foo] }
      given_rule(->{ ~v }, v: Var) { |v:| Splat.new(v.name) }
      expect_success_on [1, 2, 3], foo: [2, 3]
    end
    it 'array-style object matches' do
      given_pattern { TFoo[a, b] }
      given_rule(->{ klass[*field_pats] }, klass: [Class, Module], field_pats: Var) do |klass:, field_pats:|
        Obj.new(klass, field_pats.map { |f| [f.name, f] }.to_h)
      end
      expect_success_on TFoo.new(1, 2), a: 1, b: 2
      expect { transform { foo[a, b] } }.to raise_error("Invalid pattern: foo[a, b]")
    end
    it 'hash-style object matches' do
      given_pattern { TFoo[a: x, b: y] }
      given_rule(->{ klass[field_pats] }, klass: [Class, Module], field_pats: Hash) do |klass:, field_pats:|
        Obj.new(klass, field_pats)
      end
      expect_success_on TFoo.new(1, 2), x: 1, y: 2
    end
    it 'allows matched vars to be locals' do
      foo = nil
      v = nil
      given_pattern { [1, ~foo] }
      given_rule(->{ ~v }, v: Var) { |v:| Splat.new(v.name) }
      expect_success_on [1, 2, 3], foo: [2, 3]
    end
    it 'translates stuff with hashes' do
      given_pattern { {a: 1, b: [1, foo]} }
      expect_success_on({a: 1, b: [1, 2]}, foo: 2)
    end
    it 'translates underscores' do
      given_pattern { [_, a] }
      given_rule(->{ v }, v: Var) do |v:|
        raise Transformer::NotApplicable unless v.name == :_
        Any
      end
      expect_success_on [1, 2], a: 2
      expect_success_on [3, 4], a: 4
    end


    it 'PatternBase' do
      tx = RuleSets::PatternBase.method(:transform)
      x_var = tx.call { x }
      expect(x_var).to be_a Var
      expect(x_var.name).to eql :x

      x_const = tx.call { TFoo }
      expect(x_const).to eql TFoo
    end
    it 'metacircularish' do
      t = Transformer.from(Transformer::PatternBase) do
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
    # it 'transforms recursively' do
    #   t = Transformer.from(Transformer::StandardPattern) do
    #     add_rule(->{ n(type, children) }) do |type:, children:|
    #       quote { ::Parser::AST::Node[type: !type, children: !children] }
    #     end
    #   end
    #   pat = t.transform { n(:send, [nil, var_name]) }
    #   cp = Compiler.compile(pat)
    #   x = ExprCache.get(->{ asdf })
    #   e = cp.match(x)
    #   expect(e.var_name).to eql :asdf
    # end
    it 'quote' do
      a = quote { 1 }
      r = quote { [!a, 2] }
      expect(r.type).to eql :array
      expect(r.children.map { |c| c.children[0] }).to eql [1, 2]

      r = quote do
        [!(quote { 1 }), 2]
      end
      expect(r.type).to eql :array
      expect(r.children.map { |c| c.children[0] }).to eql [1, 2]
    end
    # it 'test' do
    #   r1 = ExprCache.get(->{c[fs]})
    #   r2 = ExprCache.get(->{c[*fs]})
    #   r3 = ExprCache.get(->{c[a, b]})
    #   r4 = ExprCache.get(->{c[a: x, b: y]})
    #   r4
    # end
    # it 'test2' do
    #   x = [1, 3]
    #   r = ExprCache.get(proc do
    #     case x
    #     when match([1, 2])
    #       :one_two
    #     when match([1, 3])
    #       :one_three
    #     else
    #       :fell_through
    #     end
    #   end)
    #   r = ExprCache.get(proc do
    #     if match [1, 2]
    #       body1
    #     elsif match [1, 3]
    #       body2
    #     else
    #       :fell_through
    #     end
    #   end)
    #   puts r
    #
    #   # t = Transformer.from(Transformer::Pattern) do
    #   #   add_rule(-> do
    #   #     match value
    #   #     when(test1)
    #   #     body1
    #   #   end) do |klass:, fields:|
    #   #     raise Transformer::NotApplicable unless klass.is_a?(Class) || klass.is_a?(Module)
    #   #     Obj.new(klass, fields)
    #   #   end
    #   # end
    #   #
    #   # r
    # end
  end
end
