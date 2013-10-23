require 'sourcify'
require_relative 'helpers'
require 'sexp_transformer'

def sexp(&block)
  block.to_sexp(strip_enclosure: true, ignore_nested: true).to_a
end

def transform(sp)
  Destructure::SexpTransformer.new.transform(sp)
end

describe Destructure::SexpTransformer do

  it 'should transform underscore to wildcard' do
    v = transform(sexp { _ })
    v.should == Dmatch::_
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
    Dmatch::match(Obj.of_type(Obj, fields: {
        x: Obj.of_type(Var, :name => :x),
        y: Obj.of_type(Var, :name => :y)
    }), result).
        should be_instance_of Env
  end

  it 'should transform object matchers with explicit names' do
    result = transform(sexp { Object(x: a, y: 2) })
    Dmatch::match(Obj.of_type(Obj, fields: {
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

  it 'should transform regexps' do
    transform(sexp { /foo/ }).should == /foo/
  end

  it 'should transform the empty hash' do
    transform(sexp { {} }).should == Hash.new
  end

end