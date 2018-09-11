# frozen_string_literal: true

require 'destruct'
require 'time_it'

class Destruct
  describe Transformer do
    Foo = Struct.new(:a, :b)
    it 'Ruby' do
      t = Transformer::Ruby
      expect(t.transform { 1 }).to eql 1
      expect(t.transform { 2.0 }).to eql 2.0
      expect(t.transform { :x }).to eql :x
      expect(t.transform { 'x' }).to eql 'x'

      x_var = t.transform { x }
      expect(x_var).to be_a Transformer::VarRef
      expect(x_var.name).to eql :x

      x_const = t.transform { Foo }
      expect(x_const).to be_a Transformer::ConstRef
      expect(x_const.fqn).to eql 'Foo'

      x_case = t.transform do
        case 1
        when 2
          3
        when 4
          5
        else
          6
        end
      end
      expect(x_case).to be_a Transformer::Case
      expect(x_case.value).to eql 1
      expect(x_case.whens[0].pred).to eql 2
      expect(x_case.whens[0].body).to eql 3
      expect(x_case.whens[1].pred).to eql 4
      expect(x_case.whens[1].body).to eql 5
      expect(x_case.else_body).to eql 6
    end
    it 'Pattern' do
      t = Transformer::PatternBase
      x_var = t.transform { x }
      expect(x_var).to be_a Var
      expect(x_var.name).to eql :x

      x_const = t.transform { Foo }
      expect(x_const).to eql Foo
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
    it 'array-style object matches' do
      t = Transformer.from(Transformer::PatternBase) do
        add_rule(->{ klass[*field_pats] }) do |klass:, field_pats:|
          raise Transformer::NotApplicable unless klass.is_a?(Class) || klass.is_a?(Module)
          Obj.new(klass, field_pats.map { |f| [f.name, f] }.to_h)
        end
      end

      cp = Compiler.compile(t.transform { Foo[a, b] })
      e = cp.match(Foo.new(1, 2))
      expect(e.a).to eql 1
      expect(e.b).to eql 2

      r = t.transform { foo[a, b] }
      expect(r[0]).to eql :unmatched_expr
    end
    it 'hash-style object matches' do
      t = Transformer.from(Transformer::PatternBase) do
        add_rule(->{ klass[fields] }) do |klass:, fields:|
          raise Transformer::NotApplicable unless klass.is_a?(Class) || klass.is_a?(Module)
          Obj.new(klass, fields)
        end
      end

      cp = Compiler.compile(t.transform { Foo[a: x, b: y] })
      e = cp.match(Foo.new(1, 2))
      expect(e.x).to eql 1
      expect(e.y).to eql 2
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
