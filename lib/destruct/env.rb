# frozen_string_literal: true

require 'stringio'
require_relative './types'

class Destruct
  # Holds the variables bound during pattern matching. For many patterns, the variable
  # names are known at compilation time, so Env.new_class is used to create a derived
  # Env that can hold exactly those variables. If a pattern contains a Regex, Or, or
  # Unquote, then the variables bound are generally not known until the pattern is matched
  # against a particular object at run time. The @extras hash is used to bind these variables.
  class Env
    NIL = Object.new
    UNBOUND = :__unbound__

    def method_missing(name, *args, &block)
      name_str = name.to_s
      if name_str.end_with?('=')
        @extras ||= {}
        @extras[name_str[0..-2].to_sym] = args[0]
      else
        if @extras.nil?
          Destruct::Env::UNBOUND
        else
          @extras.fetch(name) { Destruct::Env::UNBOUND }
        end
      end
    end

    def initialize(regexp_match_data=nil)
      if regexp_match_data
        @extras = regexp_match_data.names.map { |n| [n.to_sym, regexp_match_data[n]] }.to_h
      end
    end

    def env_each
      if @extras
        @extras.each_pair { |k, v| yield(k, v) }
      end
    end

    def env_keys
      result = []
      env_each { |k, _| result.push(k) }
      result
    end

    # deprecated
    def [](var_name)
      self.send(var_name)
    end

    # only for dynamic binding
    def []=(var_name, value)
      self.send(:"#{var_name}=", value)
    end

    def bind(var, val)
      send(:"#{var}=", val)
      self
    end

    def to_s
      kv_strs = []
      env_each do |k, v|
        kv_strs << "#{k}=#{v.inspect}"
      end
      "#<Env: #{kv_strs.join(", ")}>"
    end
    alias_method :inspect, :to_s

    def self.new_class(*var_names)
      Class.new(Env) do
        attr_accessor(*var_names)
        eval <<~CODE
          def initialize
            #{var_names.map { |v| "@#{v} = :__unbound__" }.join("\n")}
          end

          def env_each
            #{var_names.map { |v| "yield(#{v.inspect}, @#{v})" }.join("\n")}
            if @extras
              @extras.each_pair { |k, v| yield(k, v) }
            end
          end

          def self.name; "Destruct::Env"; end
        CODE
      end
    end
  end
end
