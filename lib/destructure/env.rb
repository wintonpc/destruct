require 'ostruct'
require 'destructure/dmatch'
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

    def bind(identifier, value)
      raise 'identifier must be a Var' unless identifier.is_a? Var
      value_to_store = value.nil? ? EnvNil.new : value
      existing_key = env.keys.select{|k| k == identifier || (k.name.is_a?(Symbol) && k.name == identifier.name)}.first
      return nil if existing_key &&
          (Dmatch.match(env[existing_key], value_to_store).nil? ||
          Dmatch.match(value_to_store, env[existing_key]).nil?)
      env[existing_key || identifier] = value_to_store
      self
    end

    alias []= bind

    def keys
      env.keys
    end

    def to_openstruct
      OpenStruct.new(Hash[env.map{|kv| [kv.first.name, kv.last]}])
    end

    def merge!(other_env)
      other_env.keys.any?{|k| bind(k, other_env[k]).nil?} ? nil : self
    end

    class EnvNil; end
  end
end