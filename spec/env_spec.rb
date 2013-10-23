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
    @env[v].should == 5
  end

  it 'should require identifiers to be Vars' do
    expect { @env[:x] }.to raise_exception
    expect { @env[:x] = 5 }.to raise_exception
  end

  it 'should allow rebinding to a matching value' do
    v = Var.new
    @env.bind(v, 5)
    @env.bind(v, 5).should be_instance_of Env
    @env[v].should == 5
  end

  it 'should not allow rebinding to a different value' do
    v = Var.new
    @env.bind(v, 5)
    @env.bind(v, 6).should be_nil
    @env[v].should == 5
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
    c = Var.new(:c)
    d = Var.new(:d)
    @env[c] = 66
    @env[d] = 88

    e2 = Env.new
    s = Var.new(:s)
    t = Var.new(:t)
    e2[s] = 43
    e2[t] = 55
    @env.merge!(e2).should == @env

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
    @env.merge!(e2).should be_nil
  end
end