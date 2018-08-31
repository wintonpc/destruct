# frozen_string_literal: true

require 'ostruct'
require 'destructure/dmatch'
require 'destructure/types'

class DMatch
  class Env
    def initialize
      @env = [] # [Var, Object] pairs
    end

    def [](identifier)
      v = look_up(identifier)
      raise "Identifier '#{identifier}' is not bound." if v.nil?
      massage_value_out(v)
    end

    def fetch(identifier)
      v = look_up(identifier)
      if v.nil?
        yield
      else
        massage_value_out(v)
      end
    end

    private def look_up(identifier)
      raise 'identifier must be a Var or symbol' unless identifier.is_a?(Var) || identifier.is_a?(Symbol)
      @env.each do |k, v|
        return v if k == identifier || k.name == identifier
      end
      nil
    end

    private def massage_value_in(v)
      v.nil? ? NIL : v
    end

    private def massage_value_out(v)
      v == NIL ? nil : v
    end

    def bind(identifier, value)
      raise 'identifier must be a Var' unless identifier.is_a?(Var)
      value = massage_value_in(value)
      @env.each do |k, existing_value|
        if k == identifier
          if DMatch.match(existing_value, value).nil? || DMatch.match(value, existing_value).nil?
            return nil # unification failure
          else
            return self # unification success
          end
        end
      end

      # key doesn't exist. add it.
      @env << [identifier, value]
      self
    end

    alias []= bind

    def each_key
      @env.each { |k, _v| yield k }
    end

    def merge!(other_env)
      other_env.each_key do |k|
        return nil if bind(k, other_env[k]).nil?
      end
      self
    end

    NIL = Object.new
  end
end
