class Destruct
  module RuleSets
    class AstValidator
      class << self
        def validate(x)
          if x.is_a?(Parser::AST::Node)
            if !x.type.is_a?(Symbol)
              raise "Invalid pattern: #{x}"
            end
            x.children.each { |v| validate(v) }
          elsif !x.primitive?
            raise "Invalid pattern: #{x}"
          end
        end
      end
    end
  end
end
