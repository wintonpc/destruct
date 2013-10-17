require 'singleton'

class Var
  attr_reader :name

  def initialize(name=nil)
    @name = name
  end
end

class Splat < Var

end

class Obj
  attr_reader :fields

  def initialize(fields)
    @fields = fields
  end
end