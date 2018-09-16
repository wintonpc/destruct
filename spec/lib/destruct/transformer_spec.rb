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
    # broken
    # it 'transforms recursively' do
    #   given_pattern { n(:send, [nil, var_name]) }
    #   given_rule(->{ n(type, children) }) do |type:, children:|
    #     quote { ::Parser::AST::Node[type: !type, children: !children] }
    #   end
    #   expect_success_on ExprCache.get(->{ asdf }), var_name: :asdf
    # end
    it 'quote' do
      # pretty much broken for anything non-trivial.
      # One problem is knowing which symbols to wrap when unpacking (UnpackAst), e.g.
      # (send _ :[] _) should keep transforming the underscores but shouldn't transform
      # :[] into (sym :[]). At a minimum, need to add per-node-type rules in UnpackAst
      a = quote { 1 } # can be quoted
      b = 2           # or unquoted
      r = quote { [!a, !b, 3] }
      expect(r.type).to eql :array
      expect(r.children.map { |c| c.children[0] }).to eql [1, 2, 3]

      s = quote { a(b) }
      r = quote { 1 + !s }
      expect(r.to_s1).to eql ExprCache.get(->{1 + a(b)}).to_s1

      s = quote { c.a(b) }
      r = quote { 1 + !s }
      expect(r.to_s1).to eql ExprCache.get(->{1 + c.a(b)}).to_s1

      s = quote { ExprCache }
      r = quote { 1 + !s }
      expect(r.to_s1).to eql ExprCache.get(->{1 + ExprCache}).to_s1

      # quote/unquote/quote is currently broken
      # r = quote do
      #   [!(quote { 1 }), 2]
      # end
      # expect(r.type).to eql :array
      # expect(r.children.map { |c| c.children[0] }).to eql [1, 2]
    end
  end
end
