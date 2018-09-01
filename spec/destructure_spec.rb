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

  it 'should handle unquoted values' do
    foo = 7
    @my_var = 9

    expect(destructure(5) do
      match { !5 }
    end).to eql true

    expect(destructure(7) do
      match { !foo }
    end).to eql true

    expect(destructure(9) do
      match { !@my_var }
    end).to eql true
  end

  it 'should handle unquoted patterns' do
    a_literal = DMatch::SexpTransformer.transform(proc { :int | :float | :str })
    expect(destructure([:float, 3.14]) do
      if match { [!a_literal, val] }
        val
      end
    end).to eql 3.14
  end

  it 'allows unquoted values to change between calls' do
    log = []
    local = 0
    p = proc { !local }

    destructure(0) { log << match(&p) }
    destructure(1) { log << match(&p) }
    local = 1
    destructure(0) { log << match(&p) }
    destructure(1) { log << match(&p) }
    expect(log).to eql [true, false, false, true]
  end

  # it 'allows multiple procs per line' do
  #   expect(destructure(5) { match { !5 } }).to eql true
  # end

  def package(v, extra: nil)
    {packaged: v, extra: extra}
  end
end
