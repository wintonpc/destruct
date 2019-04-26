require 'ast'

def make_singleton(inspect_str)
  obj = Object.new
  obj.define_singleton_method(:to_s) { inspect_str }
  obj.define_singleton_method(:inspect) { inspect_str }
  obj
end

class Object
  def primitive?
    is_a?(Numeric) || is_a?(String) || is_a?(Symbol) || is_a?(Regexp) || self == true || self == false || self == nil
  end
end

module Parser
  module AST
    class Node < ::AST::Node
      def to_s1
        to_s.gsub(/\s+/, " ")
      end
    end
  end
end
