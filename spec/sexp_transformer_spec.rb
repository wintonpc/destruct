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
    expect(v).to eql Dmatch::_
  end

  it 'should transform vars' do
    v = transform(sexp { x })
    expect(v).to be_instance_of Var
    expect(v.name).to eql :x
  end

  it 'should transform splats' do
    v = transform(sexp { @@x })
    expect(v).to be_instance_of Splat
    expect(v.name).to eql :x
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
    expect(Dmatch::match(Obj.of_type(Obj, fields: {
        x: Obj.of_type(Var, :name => :a),
        y: 2
    }), result)).to be_instance_of Env
  end

  it 'should transform object matchers using the constant as a predicate' do
    v = transform(sexp { Numeric() })
    expect(v.test(5)).to be_true
    expect(v.test(4.5)).to be_true
    expect(v.test(Object.new)).to be_false
  end

  it 'should allow object matchers to omit the parentheses' do
    expect(transform(sexp { Numeric })).to be_instance_of Obj
  end

  it 'should transform primitives' do
    expect(transform(sexp { 1 })).to eql 1
    expect(transform(sexp { 2.3 })).to eql 2.3
    expect(transform(sexp { true })).to eql true
    expect(transform(sexp { false })).to eql false
    expect(transform(sexp { nil })).to eql nil
  end

  it 'should transform strings' do
    expect(transform(sexp { 'hello' })).to eql 'hello'
    expect(transform(sexp { "hello #{'there'}" })).to eql 'hello there'
  end

  it 'should transform arrays' do
    expect(transform(sexp { [] })).to eql []
    expect(transform(sexp { [1,'hi',true] })).to eql [1,'hi',true]
  end

  it 'should transform hashes' do
    expect(transform(sexp { {a: 1, b: 2} })).to eql({a: 1, b: 2})
    expect(transform(sexp { {a: 1, b: 2} })).to eql({b: 2, a: 1})
  end

  it 'should transform regexps' do
    expect(transform(sexp { /foo/ })).to eql /foo/
  end

  it 'should transform the empty hash' do
    expect(transform(sexp { {} })).to eql Hash.new
  end

end