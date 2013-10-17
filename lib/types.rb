class Var
  attr_reader :name

  def initialize(name=nil)
    @name = name
  end
end

class Splat < Var

end

class Wildcard < Var
  def initialize
    super('_')
  end
end

class Obj
  attr_reader :fields

  def initialize(fields)
    @fields = fields
  end
end