require_relative 'helpers'
require 'pmatch'

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

describe 'pmatch' do
  it 'should match non-local vars' do
    a = 1
    e = pmatch(a) { x }
    e.x.should == 1
  end
  it 'should match local vars' do
    a = 1
    x = 99
    e = pmatch(a) { x }
    e.x.should == 1
  end
  it 'should match arrays' do
    a = [1, 2, 3]
    e = pmatch(a) { [1, x, 3] }
    e.x.should == 2
  end
  it 'should match hashes' do
    h = { a: 1, b: 2, c: 3}
    e = pmatch(h) { { a: one, b: 2} }
    e.one.should == 1
  end
  it 'should match object types' do
    pmatch(5) { Numeric }.should be_true
    pmatch(99.999) { Numeric }.should be_true
    pmatch('hello') { Numeric }.should be_false
  end
  it 'should match object fields' do
    e = pmatch(Foo.new(1, 2)) { Foo(a, b) }
    e.a.should == 1
    e.b.should == 2

    pmatch(Foo.new(3, 4)) { Foo(a: 3, b: b) }.b.should == 4

    pmatch(Foo.new(3, 4)) { Foo(a: 99, b: b) }.should be_false
  end
  it 'should match deeply' do
    a = [ 100, { a: 1, b: 'hi', c: Bar.new(10, [13, 17, 23, 27, 29]) } ]
    e = pmatch(a) { [ 100, { a: _, b: 'hi', c: Bar(x: ten, y: [_, 17, @@primes]) }, @@empty] }
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