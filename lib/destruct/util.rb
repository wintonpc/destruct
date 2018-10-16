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

  def unpack_constants(mod)
    mod.constants.each { |c| Object.const_set(c, mod.const_get(c)) }
  end
end

module Parser
  module AST
    class Node
      def to_s1
        to_s.gsub(/\s+/, " ")
      end
    end
  end
end
