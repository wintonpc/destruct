require 'destruct'
require 'ostruct'
require_relative '../transformer_helpers'

class Destruct
  module RuleSets
    module StdPatSpecs
      Bar = Struct.new(:a, :b)
      describe StandardPattern do
        include TransformerHelpers
        before(:each) { @rule_set ||= RuleSets::StandardPattern }
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
        it 'type constraint' do
          given_pattern { is_a?(Bar) }
          expect_success_on Bar.new(1, 2)
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
        it 'strict' do
          given_pattern { strict([{a: x, b: y}]) }
          expect_success_on [{a: 1, b: 2}]
          expect_failure_on [{a: 1}]
          expect_failure_on [{a: 1, b: 2, c: 3}]
        end
        it 'unquote' do
          given_binding binding
          h = {sub_pat: Var.new(:a)}
          given_pattern { [1, !h[:sub_pat]] }
          expect_success_on [1, 2], a: 2

          p1 = Var.new(:a)
          given_pattern { [1, !p1] }
          expect_success_on [1, 2], a: 2

          @p2 = Var.new(:a)
          given_pattern { [1, !@p2] }
          expect_success_on [1, 2], a: 2

          p3 = OpenStruct.new(pat: Var.new(:a))
          given_pattern { [1, !p3.pat] }
          expect_success_on [1, 2], a: 2
        end
        it 'let' do
          given_pattern { [1, a <= [2, b]] }
          expect_success_on [1, [2, 3]], a: [2, 3], b: 3
        end
        it 'let aliased with method' do
          given_pattern { [1, outer <= [2, b]] }
          expect_success_on [1, [2, 3]], outer: [2, 3], b: 3
        end
        def outer=(v)
        end
        it 'or' do
          given_pattern { [1, 2 | 3 | 4] }
          expect_success_on [1, 2]
          expect_success_on [1, 3]
          expect_success_on [1, 4]
          expect_failure_on [1, 5]
        end
        it 'regex' do
          given_pattern { /hello (?<name>\w+)/ }
          expect_success_on "hello alice", name: "alice"

          given_pattern { [/hello (?<hname>\w+)/, /goodbye (?<gbname>\w+)/] }
          expect_success_on ["hello alice", "goodbye bob"], hname: "alice", gbname: "bob"
        end
      end
    end
  end
end
