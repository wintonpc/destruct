# frozen_string_literal: true

require 'destruct'
require 'time_it'
require_relative './transformer_helpers'

class Destruct
  describe Transformer do
    include TransformerHelpers

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

    it 'metacircularish' do
      given_pattern { n(:send, [nil, var_name]) }
      given_rule(->{ n(type, children) }) do |type:, children:|
        Obj.new(Parser::AST::Node, type: type, children: children)
      end
      expect_success_on ExprCache.get(->{ asdf }), var_name: :asdf
    end
    it 'transforms recursively' do
      t = Transformer.from(Transformer::StandardPattern) do
        add_rule(->{ n(type, children) }) do |type:, children:|
          quote { ::Parser::AST::Node[type: !type, children: !children] }
        end
      end
      pat = t.transform { n(:send, [nil, var_name]) }
      cp = Compiler.compile(pat)
      x = ExprCache.get(->{ asdf })
      e = cp.match(x)
      expect(e.var_name).to eql :asdf
    end
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
  end
end
