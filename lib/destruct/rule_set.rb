require_relative './transformer'
require_relative './rule_sets/helpers'

class Destruct
  module RuleSet
    DEBUG = false

    def rules
      @rules ||= []
    end

    def self.included(base)
      base.extend(ClassMethods)
      base.include(RuleSets::Helpers)
    end

    module ClassMethods
      def transform(x=NOTHING, binding: nil, **hash_arg, &x_proc)
        instance.transform(x, binding: binding, **hash_arg, &x_proc)
      end

      def instance
        @instance ||= new
      end
    end

    def transform(x=NOTHING, binding: nil, **hash_arg, &x_proc)
      if x != NOTHING && x_proc
        raise "Pass either x or a block but not both"
      end
      x = x == NOTHING && x_proc.nil? ? hash_arg : x # ruby interprets a hash arg as keywords rather than a value for x
      x = x != NOTHING ? x : x_proc
      x = x.is_a?(Proc) ? ExprCache.get(x) : x
      binding ||= x_proc&.binding
      result = Transformer.transform(x == NOTHING ? x_proc : x, self, binding)
      self.validate(result) if self.respond_to?(:validate)
      result
    end

    # @param pat_or_proc [Object] One of:
    #   an AST-matching destruct pattern,
    #   a proc containing syntax to be converted into an AST-matching destruct pattern, or
    #   a class
    def add_rule(pat_or_proc, constraints={}, &translate_block)
      if pat_or_proc.is_a?(Proc)
        node = ExprCache.get(pat_or_proc)
        pat = (@meta_rule_set || RuleSets::AstToPattern).transform(node)
        rules << Transformer::Rule.new(pat, translate_block, constraints)
      else
        rules << Transformer::Rule.new(pat_or_proc, translate_block, constraints)
      end
    end

    private

    def meta_rule_set(rule_set)
      @meta_rule_set = rule_set
    end

    def add_rule_set(rule_set)
      if rule_set.is_a?(Class)
        rule_set = rule_set.instance
      end
      rule_set.rules.each { |r| rules << r }
    end
  end
end
