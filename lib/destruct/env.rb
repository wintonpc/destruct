# frozen_string_literal: true

require_relative './types'

class Destruct
  class Env
    NIL = Object.new
    UNBOUND = :__unbound__

    def self.new_class(*var_names)
      Class.new(Env) do
        attr_accessor(*var_names)
        eval <<~CODE
          def initialize
            #{var_names.map { |v| "@#{v} = :__unbound__" }.join("\n")}
          end

          # deprecated
          def [](var_name)
            self.send(var_name)
          end

          def env_each
            #{var_names.map { |v| "yield(#{v.inspect}, @#{v})" }.join("\n")}
          end

          def to_s
            "#<Env: #{var_names.map { |v| "#{v}=\#{#{v}}" }.join(", ")}>"
          end
          alias_method :inspect, :to_s
        CODE
      end
    end
  end
end
