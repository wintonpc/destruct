require_relative 'rspec_helper'
require 'runify'

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
  end
end