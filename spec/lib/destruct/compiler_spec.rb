# frozen_string_literal: true

require 'destruct'
require 'securerandom'

class Destruct
  describe Compiler do
    it 'compiles literals' do
      given_pattern 1
      expect_success_on 1
      expect_failure_on 2

      given_pattern "foo"
      expect_success_on "foo"
      expect_failure_on "bar"
    end
    it 'compiles vars' do
      given_pattern Var.new(:foo)
      expect_success_on 1, foo: 1

      given_pattern [Var.new(:foo), Var.new(:bar)]
      expect_success_on [1, 2], foo: 1, bar: 2

      given_pattern [Var.new(:foo), Var.new(:foo)]
      expect_success_on [1, 1]
      expect_failure_on [1, 2]
    end
    it 'compiles plain objs' do
      given_pattern Obj.new(Compiler)
      expect_success_on Compiler.new
      expect_failure_on 5
    end
    CFoo = Struct.new(:a, :b)
    it 'compiles objs with field patterns' do
      given_pattern Obj.new(CFoo, a: 1, b: 2)
      expect_success_on CFoo.new(1, 2)
      expect_failure_on CFoo.new(1, 3)
      expect_failure_on []
    end
    it 'compiles objs with vars' do
      given_pattern Obj.new(CFoo, a: 1, b: Var.new(:bvar))
      expect_success_on CFoo.new(1, 2), bvar: 2
    end
    it 'compiles objs with deep vars' do
      given_pattern Obj.new(CFoo, a: 1, b: Obj.new(CFoo, a: 1, b: Var.new(:bvar)))
      expect_success_on CFoo.new(1, CFoo.new(1, 2)), bvar: 2
    end
    it 'compiles ORs' do
      given_pattern Or.new(1, 2)
      expect_success_on 1
      expect_success_on 2
      expect_failure_on 3
    end
    it 'compiles deep ORs' do
      given_pattern Or.new(Obj.new(CFoo, a: 1), Obj.new(CFoo, a: 2))
      expect_success_on CFoo.new(1)
      expect_success_on CFoo.new(2)
      expect_failure_on CFoo.new(3)
    end
    it 'compiles ORs with arrays' do
      given_pattern Or.new(Obj.new(CFoo, a: [1, 2, 3]), Obj.new(CFoo, a: 4))
      expect_success_on CFoo.new(4)
    end
    it 'compiles nested ORs' do
      given_pattern Or.new(Obj.new(CFoo, a: 9, b: 1), Obj.new(CFoo, a: 9, b: Or.new(2, 3)))
      expect_success_on CFoo.new(9, 1)
      expect_success_on CFoo.new(9, 2)
      expect_success_on CFoo.new(9, 3)
      expect_failure_on CFoo.new(9, 4)
    end
    it 'compiles nested ORs with Vars' do
      given_pattern Or.new(Obj.new(CFoo, a: 1), Obj.new(CFoo, a: Or.new(2, 3), b: Var.new(:x)))
      expect_success_on CFoo.new(2, 9), x: 9
    end
    it 'compiles ORs with Vars' do
      given_pattern [Var.new(:a), Or.new([1, Var.new(:b)], [2, Var.new(:c)])]
      expect_success_on [3, [1, 7]],
                        a: 3, b: 7, c: ::Destruct::Env::UNBOUND
      expect_success_on [3, [2, 8]],
                        a: 3, b: ::Destruct::Env::UNBOUND, c: 8

      given_pattern [Var.new(:a), Or.new([1, Var.new(:a)], [2, Var.new(:a)])]
      expect_success_on [3, [1, 3]]
      expect_failure_on [3, [1, 4]]

      given_pattern Or.new([Var.new(:a), Or.new([1, Var.new(:b)], [2, Var.new(:c)])])
      expect_success_on [3, [1, 7]],
                        a: 3, b: 7, c: ::Destruct::Env::UNBOUND
    end
    it 'compiles hashes' do
      given_pattern({a: Var.new(:foo)})
      expect_success_on({a: 1}, foo: 1)
    end
    it 'compiles wildcards' do
      given_pattern([Any, Any])
      expect_success_on [1, 2]
      expect_success_on [1, 1]
      expect_failure_on [1]
      expect_failure_on [1, 2, 3]
    end
    it 'compiles lets' do
      given_pattern(Let.new(:a, [Var.new(:b), Var.new(:c)]))
      expect_success_on [1, 2], a: [1, 2], b: 1, c: 2
      expect_failure_on [1, 2, 3]
    end
    it 'compiles unquoted values' do
      given_pattern [1, Unquote.new("outer")]
      given_binding binding
      outer = 5
      expect_success_on [1, 5]
      expect_failure_on [1, 6]

      # handles changes in the binding
      outer = 6
      expect_failure_on [1, 5]
      expect_success_on [1, 6]
    end
    it 'compiles unquoted patterns' do
      given_pattern [Var.new(:a), Unquote.new("outer")]
      given_binding binding
      outer = Var.new(:b)
      expect_success_on [1, 2], a: 1, b: 2

      outer = Var.new(:a)
      expect_failure_on [1, 2]
      expect_success_on [1, 1], a: 1
    end
    it 'compiles unquoted compiled patterns' do
      given_pattern [Var.new(:a), Unquote.new("outer")]
      given_binding binding
      outer = Compiler.compile(Var.new(:b))
      expect_success_on [1, 2], a: 1, b: 2
    end
    it 'caches compiled unquoted patterns' do
      given_pattern [Var.new(:a), Unquote.new("outer")]
      given_binding binding
      outer = nil

      compiled_pats = []
      Compiler.on_compile { |pat| compiled_pats << pat }

      var_name = "x#{SecureRandom.hex(6)}".to_sym

      5.times do
        outer = Var.new(var_name)
        expect_success_on [1, 2], a: 1, var_name => 2
      end

      expect(compiled_pats.count { |p| p == Var.new(var_name) }).to eql 1
    end
    it 'compiles regexes' do
      given_pattern [Var.new(:a), /hello (?<name>\w+)/]
      expect_success_on [1, "hello alice"], a: 1, name: "alice"

      given_pattern [/hello (?<name>\w+)/, Var.new(:a)]
      expect_success_on ["hello alice", 1], a: 1, name: "alice"

      given_pattern [/hello (?<name>\w+)/, /hello (?<name>\w+)/]
      expect_success_on ["hello alice", "hello alice"]

      given_pattern [/hello (?<name>\w+)/, /hello (?<name>\w+)/]
      expect_failure_on ["hello alice", "hello bob"]
    end
    it 'compiles arrays' do
      given_pattern [1, Var.new(:foo)]
      expect_success_on [1, 2], foo: 2
      expect_failure_on [2, 2]
      expect_failure_on []
      expect_failure_on [1, 2, 3]
      expect_failure_on Object.new
    end
    it 'array edge cases' do
      given pattern: [], expect_success_on: []
      given pattern: [1], expect_failure_on: [2]
      given pattern: [1], expect_failure_on: [1, 2]
      given pattern: [1], expect_failure_on: [8, 9]
      given pattern: [1, 2], expect_failure_on: [1]
      given pattern: [8, 9], expect_failure_on: [1]
      given pattern: [1, 2], expect_success_on: [1, 2]
      given pattern: [1, 2], expect_failure_on: [8, 9]
    end
    it 'compiles nested arrays' do
      given_pattern [1, [2, [3, 4], 5], 6, 7]
      expect_success_on [1, [2, [3, 4], 5], 6, 7]
      expect_failure_on [1, [2, [3, 9], 5], 6, 7]
    end
    it 'compiles splats' do
      # splat in middle
      given pattern: [1, Splat.new(:x), 4], expect_success_on: [1, 2, 3, 4], x: [2, 3]
      given pattern: [1, Splat.new(:x), 4], expect_success_on: [1, 2, 4], x: [2]
      given pattern: [1, Splat.new(:x), 4], expect_success_on: [1, 4], x: []
      given pattern: [1, Splat.new(:x), 4], expect_failure_on: [1]

      # splat at front
      given pattern: [Splat.new(:x), 3], expect_success_on: [1, 2, 3], x: [1, 2]
      given pattern: [Splat.new(:x), 3], expect_success_on: [1, 3], x: [1]
      given pattern: [Splat.new(:x), 3], expect_success_on: [3], x: []
      given pattern: [Splat.new(:x), 3], expect_failure_on: []

      # splat at end
      given pattern: [1, Splat.new(:x)], expect_success_on: [1, 2, 3], x: [2, 3]
      given pattern: [1, Splat.new(:x)], expect_success_on: [1, 2], x: [2]
      given pattern: [1, Splat.new(:x)], expect_success_on: [1], x: []
      given pattern: [1, Splat.new(:x)], expect_failure_on: []
    end
    it 'compiles open-ended splat with enumerable' do
      en = (1..3).cycle
      e = compile([Var.new(:head), Splat.new(:tail)]).match(en)
      expect(e[:head]).to eql 1
      expect(e[:tail].take(3).to_a).to eql [2, 3, 1]

      # doesn't reevaluate
      evaluations = []
      tail = Enumerator.new do |y|
        i = 0
        while true
          evaluations << i
          y << i
          i += 1
        end
      end
      head_and_tail = compile([Var.new(:head), Splat.new(:tail)])
      e = head_and_tail.match(tail)
      expect(e[:head]).to eql 0
      e = head_and_tail.match(e[:tail])
      expect(e[:head]).to eql 1
      e = head_and_tail.match(e[:tail])
      expect(e[:head]).to eql 2
      expect(evaluations).to eql [0, 1, 2]
      expect(e[:tail]).to be_a WrappedEnumerator
      expect(e[:tail].instance_exec { @inner }).to be_an Enumerator
      expect(e[:tail].instance_exec { @inner }).to_not be_a WrappedEnumerator
    end

    def compile(pat)
      Compiler.compile(pat)
    end

    def given_pattern(pat)
      @pat = compile(pat)
    end

    def given_binding(binding)
      @binding = binding
    end

    def expect_match(x)
      expect(@pat.match(x))
    end

    def expect_success_on(x, bindings={})
      env = @pat.match(x, @binding)
      expect(env).to be_truthy
      bindings.each do |k, v|
        expect(env[k]).to eql v
      end
    end

    def given(pattern:, expect_success_on: NOTHING, expect_failure_on: NOTHING, **bindings)
      given_pattern pattern
      if expect_success_on != NOTHING
        expect_success_on expect_success_on, bindings
      else
        expect_failure_on expect_failure_on
      end
    end

    def expect_failure_on(x)
      expect(@pat.match(x, @binding)).to be_falsey
    end
  end
end
