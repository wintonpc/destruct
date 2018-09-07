# frozen_string_literal: true

require 'destruct'

class Destruct
  describe Language do
    it 'built-in rules' do
      lang = Language::Basic
      expect(lang.translate { 1 }).to eql 1
      expect(lang.translate { 2.0 }).to eql 2.0
      expect(lang.translate { :x }).to eql :x
      expect(lang.translate { 'x' }).to eql 'x'
      x_var = lang.translate { x }
      expect(x_var).to be_a Var
      expect(x_var.name).to eql :x
    end
    it 'passes matches to the block' do
      lang = Language.from(Language::Basic)
      lang.add_rule(->{ ~v }) do |v:|
        Splat.new(v.name)
      end
      foo_splat = lang.translate { ~foo }
      expect(foo_splat).to be_a Splat
      expect(foo_splat.name).to eql :foo
    end
    it 'allows matched vars to be locals' do
      lang = Language.from(Language::Basic)
      v = nil
      lang.add_rule(->{ ~v }) do |v:|
        Splat.new(v.name)
      end
      foo_splat = lang.translate { ~foo }
      expect(foo_splat).to be_a Splat
      expect(foo_splat.name).to eql :foo
    end
    it 'translates more complex rules' do
      lang = Language.from(Language::Basic)
      v = nil
      lang.add_rule(->{ ~v }) do |v:|
        Splat.new(v.name)
      end
      r = lang.translate { [1, ~foo] }
      expect(r[1]).to be_a Splat
      expect(r[1].name).to eql :foo
    end
    it 'translates stuff with hashes' do
      lang = Language.from(Language::Basic)
      v = nil
      lang.add_rule(->{ ~v }) do |v:|
        Splat.new(v.name)
      end
      r = lang.translate { {a: 1, b: [1, ~foo]} }
      expect(r).to be_a Hash
      expect(r[:b].last).to be_a Splat
    end
    it 'metacircularish' do
      lang = Language.from(Language::Basic)
      lang.add_rule(->{ n(type, children) }) do |type:, children:|
        Obj.new(Parser::AST::Node, type: type, children: children)
      end
      pat = lang.translate { n(:send, [nil, var_name]) }
      cp = Compiler.compile(pat)
      x = ExprCache.get(->{ asdf })
      e = cp.match(x)
      expect(e.var_name).to eql :asdf
    end
    # Foo = Struct.new(:a, :b)
    # it 'test' do
    #   lang = Language.from(Language::Basic)
    #   lang.add_rule(->{ n(type, children) }) do |type:, children:|
    #     Obj.new(Parser::AST::Node, type: type, children: children)
    #   end
    #   lang.add_rule(->{ Class[*fields] }) do |klass:, fields:|
    #     to_s
    #   end
    #   lang.translate { Foo[b, c] }
    #   to_s
    # end
  end
end
