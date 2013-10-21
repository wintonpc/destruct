require_relative 'helpers'
require 'deconstruct'

def sexp(&block)
  block.to_sexp.to_a.last
end

class Foo
  attr_accessor :a, :b
  def initialize(a, b)
    @a, @b = a, b
  end
end

class Bar
  attr_accessor :x, :y
  def initialize(x, y)
    @x, @y = x, y
  end
end

class ZTest
  include Deconstruct

  def one(n, acc)
    dmatch([1, n]) { [a, b] }
    acc.push b
    two(99, acc)
    acc.push b
    dmatch([1, 1000]) { [a, b] }
    acc.push b
  end

  def two(n, acc)
    dmatch([1, n]) { [a, b] }
    acc.push b
  end
end

describe 'dmatch' do

  context 'when not binding locals' do

    include Deconstruct[bind_locals: false]
    include_context 'types'

    it 'should match non-local vars' do
      a = 1
      e = dmatch(a) { x }
      e.x.should == 1
    end
    it 'should match local vars' do
      a = 1
      x = 99
      e = dmatch(a) { x }
      e.x.should == 1
    end
    it 'should match arrays' do
      a = [1, 2, 3]
      e = dmatch(a) { [1, x, 3] }
      e.x.should == 2
    end
    it 'should match hashes' do
      h = { a: 1, b: 2, c: 3}
      e = dmatch(h) { { a: one, b: 2} }
      e.one.should == 1
    end
    it 'should match object types' do
      dmatch(5) { Numeric }.should be_true
      dmatch(99.999) { Numeric }.should be_true
      dmatch('hello') { Numeric }.should be_false
    end
    it 'should match object fields' do
      e = dmatch(Foo.new(1, 2)) { Foo(a, b) }
      e.a.should == 1
      e.b.should == 2

      dmatch(Foo.new(3, 4)) { Foo(a: 3, b: b) }.b.should == 4

      dmatch(Foo.new(3, 4)) { Foo(a: 99, b: b) }.should be_false
    end
    it 'should match splats' do
      a = [1,2,3,4,5,6,7,8,9]
      e = dmatch(a) { [1, @@s, 9] }
      e.s.should == [2,3,4,5,6,7,8]
    end
    it 'should match deeply' do
      a = [ 100, { a: 1, b: 'hi', c: Bar.new(10, [13, 17, 23, 27, 29]) } ]
      e = dmatch(a) { [ 100, { a: _, b: 'hi', c: Bar(x: ten, y: [_, 17, @@primes]) }, @@empty] }
      e.ten.should == 10
      e.primes.should == [ 23, 27, 29 ]
      e.empty.should == []
    end
    it 'should transform underscore to wildcard' do
      v = transform(sexp { _ })
      v.should == Decons::_
    end
    it 'should transform vars' do
      v = transform(sexp { x })
      v.should be_instance_of Var
      v.name.should == :x
    end
    it 'should transform splats' do
      v = transform(sexp { @@x })
      v.should be_instance_of Splat
      v.name.should == :x
    end
    it 'should transform object matchers with implied names' do
      result = transform(sexp { Object(x, y) })
      Decons::match(Obj.of_type(Obj, fields: {
          x: Obj.of_type(Var, :name => :x),
          y: Obj.of_type(Var, :name => :y)
      }), result).
          should be_instance_of Env
    end
    it 'should transform object matchers with explicit names' do
      result = transform(sexp { Object(x: a, y: 2) })
      Decons::match(Obj.of_type(Obj, fields: {
          x: Obj.of_type(Var, :name => :a),
          y: 2
      }), result).should be_instance_of Env
    end
    it 'should transform object matchers using the constant as a predicate' do
      v = transform(sexp { Numeric() })
      v.test(5).should be_true
      v.test(4.5).should be_true
      v.test(Object.new).should be_false
    end
    it 'should allow object matchers to omit the parentheses' do
      transform(sexp { Numeric }).should be_instance_of Obj
    end
    it 'should transform primitives' do
      transform(sexp { 1 }).should == 1
      transform(sexp { 2.3 }).should == 2.3
      transform(sexp { true }).should == true
      transform(sexp { false }).should == false
      transform(sexp { nil }).should == nil
    end
    it 'should transform strings' do
      transform(sexp { 'hello' }).should == 'hello'
      transform(sexp { "hello #{'there'}" }).should == 'hello there'
    end
    it 'should transform arrays' do
      transform(sexp { [] }).should == []
      transform(sexp { [1,'hi',true] }).should == [1,'hi',true]
    end
    it 'should transform hashes' do
      transform(sexp { {a: 1, b: 2} }).should == {a: 1, b: 2}
      transform(sexp { {a: 1, b: 2} }).should == {b: 2, a: 1}
    end
    it 'should transform the empty hash' do
      transform(sexp {   # placed on separate lines to keep sourcify from barfing
        {}               # due to hash/block syntax ambiguity. unlikely to be a
      }).should == {}    # frequent use case.
    end
  end



  context 'when binding locals' do

    include Deconstruct

    it 'should set pre-initialized local variables' do
      a = 0
      dmatch([1,2]) { [a, b] }
      a.should == 1
    end

    it 'should set non-literal local variables' do
      a = 0
      dmatch([OpenStruct.new(hi: 'hello'), 2]) { [a, b] }
      a.should be_instance_of OpenStruct
      a.hi.should == 'hello'
    end

    it 'should create methods for non-initialized local variables' do
      dmatch([1,2]) { [a, b] }
      b.should == 2
    end

    it 'should ensure the fake locals maintain scope like real locals' do
      acc = []
      ZTest.new.one(3, acc)
      acc.should == [3, 99, 3, 1000]
    end

    it 'should make fake locals private' do
      f = ZTest.new
      f.one(3, [])
      expect { f.b }.to raise_error(NoMethodError)
    end

    it 'should restrict method_missing to only known values' do
      dmatch([1,2]) { [a, b] }
      b.should == 2
      expect { self.c }.to raise_error(NoMethodError)
    end

    def important_method
      42
    end

    it 'should disallow non-local pattern variables with the same name as methods' do
      expect { dmatch([1,2]) { [a, important_method] } }.to raise_exception
    end

    it 'should return nil for non-matches' do
      dmatch([1,2]) { [5, b] }.should be_nil
    end
  end
end