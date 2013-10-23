require_relative 'helpers'
require 'destructure'

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
  include Destructure

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

describe 'Destructure#dmatch' do

  context 'always' do

    include Destructure[bind_locals: false]
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

    it 'should match regexps' do
      h = { a: 1, b: 'matching is the best' }
      e = dmatch(h) { { a: 1, b: /(?<what>\w+) is the best/} }
      e.what.should == 'matching'

      h = { a: 1, b: 'ruby is the worst' }
      dmatch(h) { { a: 1, b: /(?<what>\w+) is the best/} }.should be_nil
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

  end


  context 'when binding locals' do

    include Destructure # binds locals by default

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