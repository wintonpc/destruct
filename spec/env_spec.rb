require_relative 'helpers'
require 'env'

describe Dmatch::Env do

  include_context 'types'

  before :each do
    @env = Env.new
  end

  it 'should bind identifiers to values' do
    v = Var.new
    @env[v] = 5
    expect(@env[v]).to eql 5
  end

  it 'should require identifiers to be Vars' do
    expect { @env[:x] }.to raise_exception
    expect { @env[:x] = 5 }.to raise_exception
  end

  it 'should allow rebinding to a matching value' do
    v = Var.new
    @env.bind(v, 5)
    expect(@env.bind(v, 5)).to be_instance_of Env
    expect(@env[v]).to eql 5
  end

  it 'should not allow rebinding to a different value' do
    v = Var.new
    @env.bind(v, 5)
    expect(@env.bind(v, 6)).to be_nil
    expect(@env[v]).to eql 5
  end

  it 'should allow nil to be set' do
    v = Var.new
    expect { @env[v] }.to raise_exception
    @env[v] = nil
    expect(@env[v]).to eql nil
  end

  it 'should allow false to be set' do
    v = Var.new
    @env[v] = false
    expect(@env[v]).to eql false
  end

  it 'should allow getting by var name' do
    @env[Var.new(:v)] = 42
    expect(@env[:v]).to eql 42
  end

  it 'should allow merging' do
    c = Var.new(:c)
    d = Var.new(:d)
    @env[c] = 66
    @env[d] = 88

    e2 = Env.new
    s = Var.new(:s)
    t = Var.new(:t)
    e2[s] = 43
    e2[t] = 55
    expect(@env.merge!(e2)).to eql @env

    expect(@env[c]).to eql 66
    expect(@env[d]).to eql 88
    expect(@env[s]).to eql 43
    expect(@env[t]).to eql 55

  end

  it 'should not overwrite keys when merging' do
    c = Var.new
    @env[c] = 66

    e2 = Env.new
    s = c
    e2[s] = 43
    expect(@env.merge!(e2)).to be_nil
  end
end