require 'sourcify'
require_relative 'helpers'
require 'sexp_transformer'

def sexp(&block)
  block.to_sexp(strip_enclosure: true, ignore_nested: true).to_a
end

def transform(sp, caller_binding=nil)
  Destructure::SexpTransformer.new(caller_binding || binding).transform(sp)
end

describe Destructure::SexpTransformer do

  include_context 'types'

  it 'should transform underscore to wildcard' do
    v = transform(sexp { _ })
    expect(v).to eql DMatch::_
  end

  it 'should transform local vars' do
    v = transform(sexp { x })
    expect(v).to be_instance_of Var
    expect(v.name).to eql :x
  end

  it 'should transform instance vars' do
    v = transform(sexp { @my_var })
    expect(v).to be_instance_of Var
    expect(v.name).to eql '@my_var'
  end

  it 'should transform chained LHSs with method bases' do
    v = transform(sexp { one.two.three })
    expect(v).to be_instance_of Var
    expect(v.name).to eql 'one.two.three'
  end

  it 'should transform chained LHSs with instance variable bases' do
    v = transform(sexp { @one.two.three })
    expect(v).to be_instance_of Var
    expect(v.name).to eql '@one.two.three'
  end

  it 'should transform chained LHSs with arguments' do
    v = transform(sexp { one(11).two([22, 33]).three })
    expect(v).to be_instance_of Var
    expect(v.name).to eql 'one(11).two([22, 33]).three'
  end

  it 'should transform chained LHSs with hashes' do
    v = transform(sexp { @one.two[1].three })
    expect(v).to be_instance_of Var
    expect(v.name).to eql '@one.two[1].three'
  end

  it 'should transform hash LHSs' do
    v = transform(sexp { one[:foo] })
    expect(v).to be_instance_of Var
    expect(v.name).to eql 'one[:foo]'
  end

  it 'should transform splats' do
    v = transform(sexp { @@x })
    expect(v).to be_instance_of Splat
    expect(v.name).to eql :x
  end

  it 'should transform object matchers with implied names' do
    result = transform(sexp { Object[x, y] })
    DMatch::match(Obj.of_type(Obj, fields: {
        x: Obj.of_type(Var, :name => :x),
        y: Obj.of_type(Var, :name => :y)
    }), result).
        should be_instance_of Env
  end

  it 'should transform Hash matchers with implied names' do
    result = transform(sexp { Hash[x, y] })

    expect(DMatch::match({ x: Obj.of_type(Var, :name => :x),
                           y: Obj.of_type(Var, :name => :y) }, result)).to be_instance_of Env
  end

  it 'should transform object matchers with explicit names' do
    result = transform(sexp { Object[x: a, y: 2] })
    expect(DMatch::match(Obj.of_type(Obj, fields: {
        x: Obj.of_type(Var, :name => :a),
        y: 2
    }), result)).to be_instance_of Env
  end

  it 'should transform Hash matchers with explicit names' do
    # this case is already covered completely by the normal
    # curly-brace hash matcher, but is included for completeness
    result = transform(sexp { Hash[x: a, y: 2] })  # equivalent to { x: a, y: 2 }
    expect(DMatch::match({ x: Obj.of_type(Var, :name => :a),
                           y: 2
                         }, result)).to be_instance_of Env
  end

  it 'should transform object matchers using the constant as a predicate' do
    v = transform(sexp { Numeric[] })
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

  it 'should transform lets with local LHSs' do
    v = transform(sexp { ['hello', you = /.*!/ ] })
    expect(v.last).to be_instance_of Var
    expect(v.last.name).to eql :you
    expect(v.last.test('World!', Env.new)).to be_true
    expect(v.last.test('bad', Env.new)).to be_false
  end

  it 'should transform lets with ivar LHSs' do
    v = transform(sexp { ['hello', @thing = /.*!/ ] })
    expect(v.last).to be_instance_of Var
    expect(v.last.name).to eql :@thing
    expect(v.last.test('World!', Env.new)).to be_true
    expect(v.last.test('bad', Env.new)).to be_false
  end

  it 'should transform lets with complicated LHSs' do
    v = transform(sexp { ['hello', @one.two[1].three = /.*!/ ] })
    expect(v.last).to be_instance_of Var
    expect(v.last.name).to eql '@one.two[1].three'
    expect(v.last.test('World!', Env.new)).to be_true
    expect(v.last.test('bad', Env.new)).to be_false
  end

  it 'should transform the pipe operator to a set of alternative patterns' do
    v = transform(sexp { :foo | :bar })
    expect(v).to be_an_instance_of Or
    expect(v.patterns).to eql [:foo, :bar]

    v = transform(sexp { :foo | :bar | :grill | :baz })
    expect(v).to be_an_instance_of Or
    expect(v.patterns).to eql [:foo, :bar, :grill, :baz]
  end

  it 'should transform literal variable values' do
    foo = 7
    @my_var = 9

    expect(transform(sexp { !5 }, binding)).to eql 5
    expect(transform(sexp { !foo }, binding)).to eql 7
    expect(transform(sexp { !@my_var }, binding)).to eql 9

  end

end