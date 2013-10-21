require_relative 'helpers'
require 'deconstruct'
require 'ostruct'

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

describe 'binding locals' do

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