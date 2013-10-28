require_relative 'helpers'
require 'magic'

describe 'magic' do

  context 'when performing magic' do

    it 'maintains typical =~ behavior' do
      expect('foo123' =~ /^foo/).to be_true
      expect(/^foo/ =~ 'foo123').to be_true
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

  end
end