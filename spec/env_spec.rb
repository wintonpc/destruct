require_relative 'helpers'
require 'env'

describe Env do

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
end