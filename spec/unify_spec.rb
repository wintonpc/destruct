require_relative 'rspec_helper'
require 'runify'

class TestObj
  attr_reader :a, :b
  def initialize(a, b)
    @a = a
    @b = b
  end
end

class TestObjWithC
  attr_reader :a, :b, :c
  def initialize(a, b, c)
    @a = a
    @b = b
    @c = c
  end
end

describe Runify do

  it 'should match primitives' do
    Runify::match(1, 2).should be_nil
    Runify::match(1, 1).should be_instance_of Env
    Runify::match(nil, nil).should be_instance_of Env
  end

  it 'should match strings' do
    Runify::match('hello', 'goodbye').should be_nil
    Runify::match('hello', 'hello').should be_instance_of Env
  end

  it 'should match arrays' do
    Runify::match([1,2], [2,1]).should be_nil
    Runify::match([1,2], [1,2,3]).should be_nil
    Runify::match([1,2], [1,2]).should be_instance_of Env
    Runify::match([1,2,[3,4,5]], [1,2,[3,4,5]]).should be_instance_of Env
  end

  it 'should match hashes' do
    Runify::match({a: 1, b: 2}, {c: 1, d: 2}).should be_nil
    Runify::match({a: 1, b: 2}, {a: 3, b: 4}).should be_nil
    Runify::match({a: 1, b: 2}, {a: 1, b: 2}).should be_instance_of Env
    Runify::match({a: 1, b: 2}, {b: 2, a: 1}).should be_instance_of Env
    Runify::match({a: 1, b: 2}, {a: 1, b: 2, c: 3}).should be_instance_of Env
    Runify::match({a: 1, b: { x: 100, y: 200 }}, {b: { y: 200, x: 100, }, a: 1}).should be_instance_of Env
  end

  it 'should assign variables' do
    x = Var.new
    y = Var.new
    Runify::match(x, 5)[x].should == 5
    #Runify::match(x, nil)[x].should == nil
    Runify::match(x, [1,2,3])[x].should == [1,2,3]
    Runify::match([1,x,3], [1,2,3])[x].should == 2
    Runify::match({a: 1, b: x}, {a: 1, c: 3, b: 2})[x].should == 2
    env = Runify::match([1,[4,x,6],y], [1,[4,5,6],3])
    env[x].should == 5
    env[y].should == 3
  end

  it 'should match wildcards' do
    Runify::match(Wildcard.new, 5)
    Runify::match(Wildcard.new, [])
    Runify::match(Wildcard.new, nil)
    Runify::match(Wildcard.new, {a: 1, b: 2})
  end

  it 'should match splats' do
    x = Splat.new
    Runify::match(x, 5)[x].should == [5]
    Runify::match(x, [5])[x].should == [5]
    Runify::match([1, x], [1, 2, 3])[x].should == [2, 3]
    Runify::match([x, 3], [1, 2, 3])[x].should == [1, 2]
    Runify::match([1, x, 5], [1, 2, 3, 4, 5])[x].should == [2, 3, 4]
    Runify::match([1, x, 4], [1, 4])[x].should == []
    Runify::match([x, 5], [5])[x].should == []
    Runify::match([5, x], [5])[x].should == []
    Runify::match([1, 2, 3, x, 4], [1, 4]).should be_nil
    Runify::match([1, x, 2, 3, 4], [1, 4]).should be_nil
    y = Splat.new
    e = Runify::match([1, x, [5, y, 8], 9], [1, 2, 3, 4, [5, 6, 7, 8], 9])
    e[x].should == [2, 3, 4]
    e[y].should == [6, 7]
  end

  it 'should match splats on infinite enumerables' do
    first = Var.new
    rest = Splat.new
    e = Runify::match([first, rest], [1,2,3].cycle.lazy)
    e[first].should == 1
    e[rest].take(5).to_a.should == [2,3,1,2,3]
  end

  it 'should match object fields' do
    Runify::match(Obj.new(a: 1, b: 2), TestObj.new(1, 2)).should be_instance_of Env
    Runify::match(Obj.new(a: 1, b: 2), TestObj.new(1, 3)).should be_nil
    Runify::match(Obj.new(a: 1, b: 2, c: 3), TestObj.new(1, 2)).should be_nil
    Runify::match(Obj.new(a: 1, b: 2), TestObjWithC.new(1, 2, 3)).should be_instance_of Env

    x = Var.new
    y = Var.new
    e = Runify::match(Obj.new(a: x, b: y), TestObj.new(1, 2))
    e[x].should == 1
    e[y].should == 2
  end

  it 'should match object fields recursively' do
    x = Var.new
    y = Var.new
    e = Runify::match(Obj.new(a: x, b: [4, y, 6]), TestObj.new(1, [4, 5, 6]))
    e[x].should == 1
    e[y].should == 5

    Runify::match(Obj.new(a: x, b: [4, y, 6]), TestObj.new(1, [4, 5, 7])).should be_nil
  end
end