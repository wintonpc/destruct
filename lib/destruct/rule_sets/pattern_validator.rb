class Destruct
  module RuleSets
    # Used to verify a transformer hasn't left any untransformed syntax around
    class PatternValidator
      class << self
        def validate(x)
          if x.is_a?(Or)
            x.patterns.each { |v| validate(v) }
          elsif x.is_a?(Obj)
            x.fields.values.each { |v| validate(v) }
          elsif x.is_a?(Let)
            validate(x.pattern)
          elsif x.is_a?(Array)
            x.each { |v| validate(v) }
          elsif x.is_a?(Strict)
            validate(x.pat)
          elsif x.is_a?(Hash)
            unless x.keys.all? { |k| k.is_a?(Symbol) }
              raise "Invalid pattern: #{x}"
            end
            x.values.each { |v| validate(v) }
          elsif !(x.is_a?(Binder) || x.is_a?(Unquote) || x.is_a?(Module) || x == Any || x.primitive?)
            raise "Invalid pattern: #{x}"
          end
        end
      end
    end
  end
end
