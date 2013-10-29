require_relative 'helpers'
require 'magic'

describe 'magic' do

  context 'when performing magic' do

    it 'maintains typical =~ behavior' do
      expect('string' =~ /ing$/).to be_true
      expect('string' =~ /ggg$/).to be_false
      expect(:string =~ /ing$/).to be_true
      expect(:string =~ /ggg$/).to be_false
      expect(/ing$/ =~ 'string').to be_true
      expect(/ggg$/ =~ 'string').to be_false
      expect(/ing$/ =~ :string).to be_true
      expect(/ggg$/ =~ :string).to be_false
    end

    it 'matches non =~ stuff' do
      thing = [1, 2, 3]
      case
        when thing =~-> { [1, x, 3] }
          "it was an array, x = #{x}"
        when thing =~-> { String }
          fail
        else
          fail
      end
    end

    it 'matches strings' do
      thing = 'hello'
      case
        when thing =~-> { [1, x, 3] }
          fail
        when thing =~-> { String }
          'it was string'
        else
          fail
      end
    end

    it 'matches symbols' do
      thing = :hello
      case
        when thing =~-> { [1, x, 3] }
          fail
        when thing =~-> { :hello }
          'it was symbol'
        else
          fail
      end
    end

    it 'works for every potentially troublesome case I can think of' do
      expect(nil =~-> { nil }).to be_instance_of OpenStruct
      expect(false =~-> { false }).to be_instance_of OpenStruct
      expect(false =~-> { nil }).to be_nil
      expect(nil =~-> { false }).to be_nil
      expect(true =~-> { true }).to be_instance_of OpenStruct
      expect(2 =~-> { 2 }).to be_instance_of OpenStruct
      expect(4.2 =~-> { 4.2 }).to be_instance_of OpenStruct
      expect(:foo =~-> { :foo }).to be_instance_of OpenStruct
      expect('foo' =~-> { 'foo' }).to be_instance_of OpenStruct
      expect(:foo =~-> { 'foo' }).to be_nil
      expect('foo' =~-> { :foo }).to be_nil
      expect([] =~-> { [] }).to be_instance_of OpenStruct
      expect(Hash.new =~-> { {} }).to be_instance_of OpenStruct
      expect('string' =~-> { /ing$/ }).to be_instance_of OpenStruct
      expect('string' =~-> { /ggg$/ }).to be_false
      expect(:string =~-> { /ing$/ }).to be_true
      expect(:string =~-> { /ggg$/ }).to be_false
      # (Regexp on LHS is not supported)
    end

  end
end