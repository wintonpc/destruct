require 'ostruct'
require 'destructure/types'

class Dmatch
  class Env

    def env
      @env ||= {}
    end

    def [](identifier)
      raise 'identifier must be a Var or symbol' unless (identifier.is_a? Var) || (identifier.is_a? Symbol)
      if identifier.is_a? Symbol
        identifier = env.keys.select{|k| k.name == identifier}.first || identifier
      end
      v = env[identifier]
      raise "Identifier '#{identifier}' is not bound." if v.nil?
      v.is_a?(EnvNil) ? nil : v
    end

    def []=(identifier, value)
      raise 'identifier must be a Var' unless identifier.is_a? Var
      raise "Identifier '#{identifier}' is already set to #{env[identifier]}" if env.include?(identifier)
      env[identifier] = value.nil? ? EnvNil.new : value
    end

    def keys
      env.keys
    end

    def to_openstruct
      OpenStruct.new(Hash[env.map{|kv| [kv.first.name, kv.last]}])
    end

    def merge!(other_env)
      other_env.keys.each{|k| self[k] = other_env[k]}
      self
    end

    class EnvNil; end
  end
end