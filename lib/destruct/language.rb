# frozen_string_literal: true

require 'destructure'
require 'active_support/core_ext/object/deep_dup'

class Destruct
  class Language
    LITERAL_TYPES = %i[int sym float str].freeze

    Rule = Struct.new(:expr, :translate)

    attr_reader :rules

    def initialize
      @rules = []
    end

    def translate(expr=nil, &pat_proc)
      expr ||= ExprCache.get(pat_proc)
      if !expr.is_a?(Parser::AST::Node)
        expr
      elsif LITERAL_TYPES.include?(expr.type)
        expr.children[0]
      elsif e = DMatch.match(n(:send, nil, v(:name)), expr)
        Var.new(e[:name])
      else
        raise "No translation rule for #{expr}"
      end
    end

    def add_rule(pat_proc, &translate)
      pat = ExprCache.get(pat_proc).deep_dup
      rules << Rule.new(pat, translate)
    end

    private

    def n(type, *children)
      DMatch::Obj.of_type(Parser::AST::Node, {type: type, children: children})
    end

    def v(name)
      DMatch::Var.new(name)
    end
  end
end
