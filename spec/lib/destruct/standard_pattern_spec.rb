require 'destruct'
require_relative './transformer_helpers'

class Destruct
  class Transformer
    describe StandardPattern do
      include TransformerHelpers
      before(:each) { @transformer ||= Transformer::StandardPattern }
      Bar = Struct.new(:a, :b)
      it 'primitive' do
        given_pattern { 1 }
        expect_success_on 1
        expect_failure_on 2
      end
      it 'var' do
        given_pattern { [1, v, 3] }
        expect_success_on [1, 2, 3], v: 2
      end
      it 'splat' do
        given_pattern { [1, ~foo] }
        expect_success_on [1, 2, 3], foo: [2, 3]
      end
      it 'array-style object' do
        given_pattern { Bar[a, b] }
        expect_success_on Bar.new(1, 2), a: 1, b: 2
      end
      it 'hash-style object' do
        given_pattern { Bar[a: x, b: y] }
        expect_success_on Bar.new(1, 2), x: 1, y: 2
      end
      it 'array' do
        given_pattern { [a, b] }
        expect_success_on [1, 2], a: 1, b: 2
      end
      it 'hash' do
        given_pattern { {a: x, b: y} }
        expect_success_on({a: 1, b: 2}, x: 1, y: 2)
      end
      it 'wildcard' do
        given_pattern { [1, _, _] }
        expect_success_on [1, 2, 3]
      end
      it 'unquote' do
        h = {sub_pat: Var.new(:a)}
        given_pattern { [1, !h[:sub_pat]] }
        given_binding binding
        expect_success_on [1, 2], a: 2
      end
    end
  end
end
