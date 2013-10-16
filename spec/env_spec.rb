require_relative 'rspec_helper'
require 'runify'

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
end