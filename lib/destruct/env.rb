# frozen_string_literal: true

require_relative './types'

class Destruct
  class Env
    # Store the env as parallel arrays instead of an array of pairs to avoid the cost of allocating an array
    # for each pair.
    #
    # Statistically, most matches fail. Don't allocate the env arrays until we actually have something to store.

    private def env_keys
      @env_keys ||= [] # Vars
    end

    private def env_values
      @env_values ||= [] # Objects
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
      env_each do |k, v|
        return v if k == identifier || k.name == identifier
      end
      nil
    end

    private def env_each
      zip_each(env_keys, env_values) { |k, v| yield(k, v) } if @env_keys
    end

    private def zip_each(as, bs)
      i = 0
      len = as.size
      while i < len
        yield(as[i], bs[i])
        i += 1
      end
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
      env_each do |k, existing_value|
        if k == identifier
          if existing_value != value # DMatch.match(existing_value, value).nil? || DMatch.match(value, existing_value).nil?
            return nil # unification failure
          else
            return self # unification success
          end
        end
      end

      # key doesn't exist. add it.
      env_keys << identifier
      env_values << value
      self
    end

    alias []= bind

    def each_key
      @env_keys&.each { |k| yield k }
    end

    def to_h
      h = {}
      env_each { |k, v| h[k] = v }
      h
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
