require_relative 'helpers'
require 'destruct'

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

describe 'Destruct#match' do

  include_context 'types'

  it 'should match primitives' do
    Destruct.match(1, 2).should be_nil
    Destruct.match(1, 1).should be_instance_of Env
    Destruct.match(nil, nil).should be_instance_of Env
  end

  it 'should match strings' do
    Destruct.match('hello', 'goodbye').should be_nil
    Destruct.match('hello', 'hello').should be_instance_of Env
  end

  it 'should match arrays' do
    Destruct.match([1,2], [2,1]).should be_nil
    Destruct.match([1,2], [1,2,3]).should be_nil
    Destruct.match([1,2], [1,2]).should be_instance_of Env
    Destruct.match([1,2,[3,4,5]], [1,2,[3,4,5]]).should be_instance_of Env
  end

  it 'should match hashes' do
    Destruct.match({a: 1, b: 2}, {c: 1, d: 2}).should be_nil
    Destruct.match({a: 1, b: 2}, {a: 3, b: 4}).should be_nil
    Destruct.match({a: 1, b: 2, c: Var.new}, {a: 1, b: 2}).should be_nil
    Destruct.match({a: 1, b: 2, c: Var.new}, {a: 1, b: 2, c: nil}).should be_instance_of Env
    Destruct.match({a: 1, b: 2}, {a: 1, b: 2}).should be_instance_of Env
    Destruct.match({a: 1, b: 2}, {b: 2, a: 1}).should be_instance_of Env
    Destruct.match({a: 1, b: 2}, {a: 1, b: 2, c: 3}).should be_instance_of Env
    Destruct.match({a: 1, b: { x: 100, y: 200 }}, {b: { y: 200, x: 100, }, a: 1}).should be_instance_of Env
  end

  it 'should assign variables' do
    x = Var.new
    y = Var.new
    Destruct.match(x, 5)[x].should == 5
    Destruct.match(x, nil)[x].should == nil
    Destruct.match(x, [1,2,3])[x].should == [1,2,3]
    Destruct.match([1,x,3], [1,2,3])[x].should == 2
    Destruct.match({a: 1, b: x}, {a: 1, c: 3, b: 2})[x].should == 2
    env = Destruct.match([1,[4,x,6],y], [1,[4,5,6],3])
    env[x].should == 5
    env[y].should == 3
  end

  it 'should support predicates with blocks' do
    Destruct.match(Pred.new{|x| x.odd? }, 5).should be_instance_of Env
    Destruct.match(Pred.new{|x| x.even? }, 5).should be_nil
  end

  it 'should support predicates with callables' do
    Destruct.match(Pred.new(lambda {|x| x.odd? }), 5).should be_instance_of Env
  end

  it 'should reject predicates with both a callable and a block' do
    expect { Destruct.match(Pred.new(lambda {|x| x.odd? }) {|x| x.even? }, 5) }.to raise_exception
  end

  it 'should support variable predicates' do
    Destruct.match(Var.new(:x) {|x| x.odd? }, 5)[:x].should == 5
    Destruct.match(Var.new(:x) {|x| x.even? }, 5).should be_nil
  end

  it 'should support object predicates' do
    x = Obj.new {|x| x.is_a?(Numeric)}
    Destruct.match(x, 4.5).should be_instance_of Env
    Destruct.match(x, true).should be_nil
  end

  it 'should have sugar for object type checking' do
    x = Obj.of_type(Numeric)
    Destruct.match(x, true).should be_nil
    Destruct.match(x, 4.5).should be_true

    x = Obj.of_type(Numeric) {|x| x.odd?}
    Destruct.match(x, true).should be_nil
    Destruct.match(x, 4).should be_nil
    Destruct.match(x, 5).should be_true
  end

  it 'should match wildcards' do
    Destruct.match(Destruct::_, 5)
    Destruct.match(Destruct::_, [])
    Destruct.match(Destruct::_, nil)
    Destruct.match(Destruct::_, {a: 1, b: 2})
  end

  it 'should match splats' do
    x = Splat.new
    Destruct.match(x, 5)[x].should == [5]
    Destruct.match(x, [5])[x].should == [5]
    Destruct.match([1, x], [1, 2, 3])[x].should == [2, 3]
    Destruct.match([x, 3], [1, 2, 3])[x].should == [1, 2]
    Destruct.match([1, x, 5], [1, 2, 3, 4, 5])[x].should == [2, 3, 4]
    Destruct.match([1, x, 4], [1, 4])[x].should == []
    Destruct.match([x, 5], [5])[x].should == []
    Destruct.match([5, x], [5])[x].should == []
    Destruct.match([1, 2, 3, x, 4], [1, 4]).should be_nil
    Destruct.match([1, x, 2, 3, 4], [1, 4]).should be_nil
    y = Splat.new
    e = Destruct.match([1, x, [5, y, 8], 9], [1, 2, 3, 4, [5, 6, 7, 8], 9])
    e[x].should == [2, 3, 4]
    e[y].should == [6, 7]
  end

  it 'should match filtering splats' do
    x = FilterSplat.new([200, Destruct::_])
    a = [[100, 1], [200, 2], [100, 3], [200, 4], [100, 5], [200, 6]]
    Destruct.match([[100, 1], x, [200, 6]], a)[x].should == [[200, 2], [200, 4]]

    x = FilterSplat.new([999, Destruct::_])
    Destruct.match([[100, 1], x, [200, 6]], a)[x].should == []
  end

  it 'should disallow Vars in filtering splat patterns' do
    expect { FilterSplat.new([200, Var.new]) }.to raise_exception
  end

  it 'should match selecting splats' do
    x = SelectSplat.new([100, Destruct::_])
    a = [[100, 1], [200, 2], [100, 3], [200, 4], [100, 5], [200, 6]]
    Destruct.match([[100, 1], x, [200, 6]], a)[x].should == [100, 3]

    x = SelectSplat.new([999, Destruct::_])
    Destruct.match([[100, 1], x, [200, 6]], a).should be_nil
  end

  it 'should allow Vars in selecting splat patterns' do
    y = Var.new
    x = SelectSplat.new([100, y])
    a = [[100, 1], [200, 2], [100, 3], [200, 4], [100, 5], [200, 6]]
    e = Destruct.match([[100, 1], x, [200, 6]], a)
    e[x].should == [100, 3]
    e[y].should == 3

    x = SelectSplat.new([999, Destruct::_])
    Destruct.match([[100, 1], x, [200, 6]], a).should be_nil
  end

  it 'should match splats on infinite enumerables' do
    first = Var.new
    rest = Splat.new
    e = Destruct.match([first, rest], [1,2,3].cycle.lazy)
    e[first].should == 1
    e[rest].take(5).to_a.should == [2,3,1,2,3]
  end

  it 'should match object fields' do
    Destruct.match(Obj.new(a: 1, b: 2), TestObj.new(1, 2)).should be_instance_of Env
    Destruct.match(Obj.new(a: 1, b: 2), TestObj.new(1, 3)).should be_nil
    Destruct.match(Obj.new(a: 1, b: 2, c: 3), TestObj.new(1, 2)).should be_nil
    Destruct.match(Obj.new(a: 1, b: 2), TestObjWithC.new(1, 2, 3)).should be_instance_of Env

    x = Var.new
    y = Var.new
    e = Destruct.match(Obj.new(a: x, b: y), TestObj.new(1, 2))
    e[x].should == 1
    e[y].should == 2
  end

  it 'should match object fields recursively' do
    x = Var.new
    y = Var.new
    e = Destruct.match(Obj.new(a: x, b: [4, y, 6]), TestObj.new(1, [4, 5, 6]))
    e[x].should == 1
    e[y].should == 5

    Destruct.match(Obj.new(a: x, b: [4, y, 6]), TestObj.new(1, [4, 5, 7])).should be_nil
  end

  it 'should match regexps' do
    e = Destruct.match(/madlibs are (?<adjective>\w+) to (?<verb>\w+)/, 'madlibs are fun to do')
    e[:adjective].should == 'fun'
    e[:verb].should == 'do'
  end
end