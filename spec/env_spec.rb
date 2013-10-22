require_relative 'helpers'
require 'env'

describe Decons::Env do

  include_context 'types'

  before :each do
    @env = Env.new
  end

  it 'should bind identifiers to values' do
    v = Var.new
    @env[v] = 5
    @env[v].should == 5
  end

  it 'should require identifiers to be Vars' do
    expect { @env[:x] }.to raise_exception
    expect { @env[:x] = 5 }.to raise_exception
  end

  it 'should not allow rebinding' do
    v = Var.new
    @env[v] = 5
    expect { @env[v] = 6 }.to raise_exception
  end

  it 'should allow nil to be set' do
    v = Var.new
    expect { @env[v] }.to raise_exception
    @env[v] = nil
    @env[v].should == nil
  end

  it 'should allow false to be set' do
    v = Var.new
    @env[v] = false
    @env[v].should == false
  end

  it 'should allow getting by var name' do
    @env[Var.new(:v)] = 42
    @env[:v].should == 42
  end

  it 'should allow merging' do
    c = Var.new
    d = Var.new
    @env[c] = 66
    @env[d] = 88

    e2 = Env.new
    s = Var.new
    t = Var.new
    e2[s] = 43
    e2[t] = 55
    @env.merge!(e2)

    @env[c].should == 66
    @env[d].should == 88
    @env[s].should == 43
    @env[t].should == 55
  end

  it 'should not overwrite keys when merging' do
    c = Var.new
    @env[c] = 66

    e2 = Env.new
    s = c
    e2[s] = 43
    expect { @env.merge!(e2) }.to raise_exception
  end
end