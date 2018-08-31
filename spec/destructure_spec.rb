require 'destructure'

describe 'destructure' do
  it 'matches stuff' do
    result = destructure([1, 2, 3]) do
      case
      when match { [1, x] }
        raise "oops"
      when match { [1, x, 3] }
        {x: x}
      when match { [1, x, 4] }
        raise "oops"
      else
        raise "oops"
      end
    end

    expect(result).to eql ({x: 2})
  end

  it 'can compose patterns' do
    a_literal = DMatch::SexpTransformer.transform(proc { :int | :float | :str })
    a_literal
  end

  it 'is transparent' do
    # Verify the destructure block can call methods (including keywords)
    # and access local variables.
    cake = 'icing'
    result = destructure([1, 2, 3]) do
      case
      when match { [1, x, 3] }
        package(x, extra: cake)
      end
    end

    expect(result).to eql ({packaged: 2, extra: 'icing'})
  end

  def package(v, extra: nil)
    {packaged: v, extra: extra}
  end
end
