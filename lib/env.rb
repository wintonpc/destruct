require 'ostruct'
require 'types'

class Env

  def env
    @env ||= {}
  end

  def [](identifier)
    raise 'identifier must be a Var or symbol' unless (identifier.is_a? Var) || (identifier.is_a? Symbol)
    if identifier.is_a? Symbol
      identifier = env.keys.select{|k| k.name == identifier}.first
    end
    v = env[identifier]
    raise "Identifier '#{identifier}' is not bound." if v.nil?
    v.is_a?(EnvNil) ? nil : v
  end

  def []=(identifier, value)
    raise 'identifier must be a Var' unless identifier.is_a? Var
    raise "Identifier '#{identifier}' is already set to #{value}" if env.include?(identifier)
    env[identifier] = value.nil? ? EnvNil.new : value
  end

  def to_openstruct
    OpenStruct.new(Hash[@env.map{|kv| [kv.first.name, kv.last]}])
  end
end

class EnvNil

end