require_relative 'helpers'
require 'dmatch'

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

describe 'Dmatch#match' do

  include_context 'types'

  it 'should match primitives' do
    expect(Dmatch.match(1, 2)).to be_nil
    expect(Dmatch.match(1, 1)).to be_instance_of Env
    expect(Dmatch.match(nil, nil)).to be_instance_of Env
  end

  it 'should match strings' do
    expect(Dmatch.match('hello', 'goodbye')).to be_nil
    expect(Dmatch.match('hello', 'hello')).to be_instance_of Env
  end

  it 'should match arrays' do
    expect(Dmatch.match([1,2], [2,1])).to be_nil
    expect(Dmatch.match([1,2], [1,2,3])).to be_nil
    expect(Dmatch.match([1,2], [1,2])).to be_instance_of Env
    expect(Dmatch.match([1,2,[3,4,5]], [1,2,[3,4,5]])).to be_instance_of Env
  end

  it 'should match hashes' do
    expect(Dmatch.match({a: 1, b: 2}, {c: 1, d: 2})).to be_nil
    expect(Dmatch.match({a: 1, b: 2}, {a: 3, b: 4})).to be_nil
    expect(Dmatch.match({a: 1, b: 2, c: Var.new}, {a: 1, b: 2})).to be_nil
    expect(Dmatch.match({a: 1, b: 2, c: Var.new}, {a: 1, b: 2, c: nil})).to be_instance_of Env
    expect(Dmatch.match({a: 1, b: 2}, {a: 1, b: 2})).to be_instance_of Env
    expect(Dmatch.match({a: 1, b: 2}, {b: 2, a: 1})).to be_instance_of Env
    expect(Dmatch.match({a: 1, b: 2}, {a: 1, b: 2, c: 3})).to be_instance_of Env
    expect(Dmatch.match({a: 1, b: { x: 100, y: 200 }}, {b: { y: 200, x: 100, }, a: 1})).to be_instance_of Env
  end

  it 'should assign variables' do
    x = Var.new
    y = Var.new
    expect(Dmatch.match(x, 5)[x]).to eql 5
    expect(Dmatch.match(x, nil)[x]).to eql nil
    expect(Dmatch.match(x, [1,2,3])[x]).to eql [1,2,3]
    expect(Dmatch.match([1,x,3], [1,2,3])[x]).to eql 2
    expect(Dmatch.match({a: 1, b: x}, {a: 1, c: 3, b: 2})[x]).to eql 2
    env = Dmatch.match([1,[4,x,6],y], [1,[4,5,6],3])
    expect(env[x]).to eql 5
    expect(env[y]).to eql 3
  end

  it 'should support predicates with blocks' do
    expect(Dmatch.match(Pred.new{|x| x.odd? }, 5)).to be_instance_of Env
    expect(Dmatch.match(Pred.new{|x| x.even? }, 5)).to be_nil
  end

  it 'should support predicates with callables' do
    expect(Dmatch.match(Pred.new(lambda {|x| x.odd? }), 5)).to be_instance_of Env
  end

  it 'should reject predicates with both a callable and a block' do
    expect { Dmatch.match(Pred.new(lambda {|x| x.odd? }) {|x| x.even? }, 5) }.to raise_exception
  end

  it 'should support variable predicates' do
    expect(Dmatch.match(Var.new(:x) {|x| x.odd? }, 5)[:x]).to eql 5
    expect(Dmatch.match(Var.new(:x) {|x| x.even? }, 5)).to be_nil
  end

  it 'should support object predicates' do
    x = Obj.new {|x| x.is_a?(Numeric)}
    expect(Dmatch.match(x, 4.5)).to be_instance_of Env
    expect(Dmatch.match(x, true)).to be_nil
  end

  it 'should have sugar for object type checking' do
    x = Obj.of_type(Numeric)
    expect(Dmatch.match(x, true)).to be_nil
    expect(Dmatch.match(x, 4.5)).to be_true

    x = Obj.of_type(Numeric) {|x| x.odd?}
    expect(Dmatch.match(x, true)).to be_nil
    expect(Dmatch.match(x, 4)).to be_nil
    expect(Dmatch.match(x, 5)).to be_true
  end

  it 'should match wildcards' do
    Dmatch.match(Dmatch::_, 5)
    Dmatch.match(Dmatch::_, [])
    Dmatch.match(Dmatch::_, nil)
    Dmatch.match(Dmatch::_, {a: 1, b: 2})
  end

  it 'should match splats' do
    x = Splat.new
    expect(Dmatch.match(x, 5)[x]).to eql [5]
    expect(Dmatch.match(x, [5])[x]).to eql [5]
    expect(Dmatch.match([1, x], [1, 2, 3])[x]).to eql [2, 3]
    expect(Dmatch.match([x, 3], [1, 2, 3])[x]).to eql [1, 2]
    expect(Dmatch.match([1, x, 5], [1, 2, 3, 4, 5])[x]).to eql [2, 3, 4]
    expect(Dmatch.match([1, x, 4], [1, 4])[x]).to eql []
    expect(Dmatch.match([x, 5], [5])[x]).to eql []
    expect(Dmatch.match([5, x], [5])[x]).to eql []
    expect(Dmatch.match([1, 2, 3, x, 4], [1, 4])).to be_nil
    expect(Dmatch.match([1, x, 2, 3, 4], [1, 4])).to be_nil
    y = Splat.new
    e = Dmatch.match([1, x, [5, y, 8], 9], [1, 2, 3, 4, [5, 6, 7, 8], 9])
    expect(e[x]).to eql [2, 3, 4]
    expect(e[y]).to eql [6, 7]
  end

  it 'should match filtering splats' do
    x = FilterSplat.new([200, Dmatch::_])
    a = [[100, 1], [200, 2], [100, 3], [200, 4], [100, 5], [200, 6]]
    expect(Dmatch.match([[100, 1], x, [200, 6]], a)[x]).to eql [[200, 2], [200, 4]]

    x = FilterSplat.new([999, Dmatch::_])
    expect(Dmatch.match([[100, 1], x, [200, 6]], a)[x]).to eql []
  end

  it 'should disallow Vars in filtering splat patterns' do
    expect { FilterSplat.new([200, Var.new]) }.to raise_exception
  end

  it 'should match selecting splats' do
    x = SelectSplat.new([100, Dmatch::_])
    a = [[100, 1], [200, 2], [100, 3], [200, 4], [100, 5], [200, 6]]
    expect(Dmatch.match([[100, 1], x, [200, 6]], a)[x]).to eql [100, 3]

    x = SelectSplat.new([999, Dmatch::_])
    expect(Dmatch.match([[100, 1], x, [200, 6]], a)).to be_nil
  end

  it 'should allow Vars in selecting splat patterns' do
    y = Var.new
    x = SelectSplat.new([100, y])
    a = [[100, 1], [200, 2], [100, 3], [200, 4], [100, 5], [200, 6]]
    e = Dmatch.match([[100, 1], x, [200, 6]], a)
    expect(e[x]).to eql [100, 3]
    expect(e[y]).to eql 3

    x = SelectSplat.new([999, Dmatch::_])
    expect(Dmatch.match([[100, 1], x, [200, 6]], a)).to be_nil
  end

  it 'should match splats on infinite enumerables' do
    first = Var.new
    rest = Splat.new
    e = Dmatch.match([first, rest], [1,2,3].cycle.lazy)
    expect(e[first]).to eql 1
    expect(e[rest].take(5).to_a).to eql [2,3,1,2,3]
  end

  it 'should match object fields' do
    expect(Dmatch.match(Obj.new(a: 1, b: 2), TestObj.new(1, 2))).to be_instance_of Env
    expect(Dmatch.match(Obj.new(a: 1, b: 2), TestObj.new(1, 3))).to be_nil
    expect(Dmatch.match(Obj.new(a: 1, b: 2, c: 3), TestObj.new(1, 2))).to be_nil
    expect(Dmatch.match(Obj.new(a: 1, b: 2), TestObjWithC.new(1, 2, 3))).to be_instance_of Env

    x = Var.new
    y = Var.new
    e = Dmatch.match(Obj.new(a: x, b: y), TestObj.new(1, 2))
    expect(e[x]).to eql 1
    expect(e[y]).to eql 2
  end

  it 'should match object fields recursively' do
    x = Var.new
    y = Var.new
    e = Dmatch.match(Obj.new(a: x, b: [4, y, 6]), TestObj.new(1, [4, 5, 6]))
    expect(e[x]).to eql 1
    expect(e[y]).to eql 5

    expect(Dmatch.match(Obj.new(a: x, b: [4, y, 6]), TestObj.new(1, [4, 5, 7]))).to be_nil
  end

  it 'should match regexps' do
    e = Dmatch.match(/madlibs are (?<adjective>\w+) to (?<verb>\w+)/, 'madlibs are fun to do')
    expect(e[:adjective]).to eql 'fun'
    expect(e[:verb]).to eql 'do'
  end

  it 'should succeed when repeated variable bindings match' do
    x = Var.new(:x)
    expect(Dmatch.match([x, 2, x], [1, 2, 1])[x]).to eql 1
    expect(Dmatch.match([x, [2, [x]]], [1, [2, [1]]])[x]).to eql 1
    expect(Dmatch.match([x, 2, x], [{a: 5, b: 6}, 2, {a: 5, b: 6}])[x]).to eql({a: 5, b: 6})
  end

  it 'should fail when repeated variable bindings do not match' do
    x = Var.new(:x)
    expect(Dmatch.match([x, 2, x], [1, 2, 3])).to be_nil
    expect(Dmatch.match([x, 2, x], [{a: 5, b: 6}, 2, {a: 5}])).to be_nil
    expect(Dmatch.match([x, 2, x], [{a: 5}, 2, {a: 5, b: 6}])).to be_nil
  end
end