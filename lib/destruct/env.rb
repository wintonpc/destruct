# frozen_string_literal: true

require 'stringio'
require_relative './types'

class Destruct
  class Env
    NIL = Object.new
    UNBOUND = :__unbound__

    def method_missing(name, *args, &block)
      if name.to_s[-1] == '='
        @extras ||= {}
        @extras[name] = args[0]
      else
        if @extras.nil?
          ::Destruct::Env::UNBOUND
        else
          @extras.fetch(name) { ::Destruct::Env::UNBOUND }
        end
      end
    end

    # deprecated
    def [](var_name)
      self.send(var_name)
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
