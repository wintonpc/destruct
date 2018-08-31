require 'ostruct'
require 'destructure/dmatch'
require 'destructure/types'

class DMatch
  class Env
    attr_reader :env

    def initialize
      @env = {}
      @keys_by_name = {}
    end

    def [](identifier)
      v = look_up(identifier)
      raise "Identifier '#{identifier}' is not bound." if v.nil?
      v.is_a?(EnvNil) ? nil : v
    end

    def fetch(identifier)
      v = look_up(identifier)
      if v.nil?
        yield
      else
        v.is_a?(EnvNil) ? nil : v
      end
    end

    private def look_up(identifier)
      raise 'identifier must be a Var or symbol' unless (identifier.is_a? Var) || (identifier.is_a? Symbol)
      if identifier.is_a? Symbol
        identifier = @keys_by_name[identifier]
      end
      v = env[identifier]
    end

    def bind(identifier, value)
      raise 'identifier must be a Var' unless identifier.is_a? Var
      value_to_store = value.nil? ? EnvNil.new : value
      existing_key = env.keys.select{|k| k == identifier || (k.name.is_a?(Symbol) && k.name == identifier.name)}.first
      return nil if existing_key &&
          (DMatch.match(env[existing_key], value_to_store).nil? ||
          DMatch.match(value_to_store, env[existing_key]).nil?)
      k = existing_key || identifier
      env[k] = value_to_store
      @keys_by_name[k.name] = k
      self
    end

    alias []= bind

    def keys
      env.keys
    end

    def each_kv
      env.each_pair { |k, v| yield(k.name, v) }
    end

    def merge!(other_env)
      other_env.keys.any?{|k| bind(k, other_env[k]).nil?} ? nil : self
    end

    class EnvNil; end
  end
end
