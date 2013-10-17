require_relative 'helpers'
require 'pmatch'

def sexp(&block)
  block.to_sexp.to_a.last
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
  #it 'should do something' do
  #  a = [1, 2, 3]
  #  e = pmatch(a) { [1, x, 3] }
  #  e.x.should == 2
  #end
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
    v = transform(sexp { Object(x, y) })
    # come back to this once predicates are implemented and use Decons::match to validate
    v.should be_instance_of Obj
    xvar = v.fields[:x]
    xvar.should be_instance_of Var
    xvar.name.should == :x
    yvar = v.fields[:y]
    yvar.should be_instance_of Var
    yvar.name.should == :y
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