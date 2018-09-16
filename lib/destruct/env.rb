# frozen_string_literal: true

require 'stringio'
require_relative './types'

class Destruct
  class Env
    NIL = Object.new
    UNBOUND = :__unbound__

    def method_missing(name, *args, &block)
      name_str = name.to_s
      if name_str[-1] == '='
        @extras ||= {}
        @extras[name_str[0..-2].to_sym] = args[0]
      else
        if @extras.nil?
          ::Destruct::Env::UNBOUND
        else
          @extras.fetch(name) { ::Destruct::Env::UNBOUND }
        end
      end
    end

    def initialize(match_data=nil)
      if match_data
        @extras = match_data.names.map { |n| [n.to_sym, match_data[n]] }.to_h
      end
    end

    def env_each
      if @extras
        @extras.each_pair { |k, v| yield(k, v) }
      end
    end

    # deprecated
    def [](var_name)
      self.send(var_name)
    end

    # only for dynamic binding
    def []=(var_name, value)
      self.send(:"#{var_name}=", value)
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
        CODE
      end
    end
  end
end
