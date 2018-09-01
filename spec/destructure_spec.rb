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

  it 'allows referenced values to change between calls' do
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

  it 'should handle binding references' do
    foo = 7
    @my_var = 9

    expect(transform(sexp { !5 })).to eql 5
    expect(transform(sexp { !foo })).to eql 7
    expect(transform(sexp { !@my_var })).to eql 9
  end

  # it 'should compose patterns' do
  #   a_literal = transform(sexp { :int | :float | :str })
  #   result = transform(sexp { [!a_literal, val] })
  #   expect(result).to dmatch [Obj.of_type(Or), Obj.of_type(Var, name: :val)]
  # end

  def package(v, extra: nil)
    {packaged: v, extra: extra}
  end
end
