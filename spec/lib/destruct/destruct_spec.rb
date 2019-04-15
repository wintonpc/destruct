# frozen_string_literal: true

require 'destruct'

describe Destruct do

  def outer_method
    9
  end

  it "matches" do
    outer_local = 8
    result = destruct([1, 2]) do
      case
      when match { [3, 4] }
        raise "oops"
      when match { [1, x] }
        [x, outer_local, outer_method]
      end
    end
    expect(result).to eql [2, 8, 9]
  end
end
