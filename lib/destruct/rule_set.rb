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

    private

    # @param pat_or_proc [Object] One of:
    #   an AST-matching destruct pattern,
    #   a proc containing syntax to be converted into an AST-matching destruct pattern, or
    #   a class
    def add_rule(pat_or_proc, constraints={}, &translate_block)
      translate = wrap_translate(translate_block, constraints)
      if pat_or_proc.is_a?(Proc)
        @meta_rule_set or raise "must specify meta_rule_set if using proc-style rules"
        node = ExprCache.get(pat_or_proc)
        pat = @meta_rule_set.transform(node)
        rules << Transformer::Rule.new(pat, translate, constraints)
      else
        rules << Transformer::Rule.new(pat_or_proc, translate, constraints)
      end
    end

    def meta_rule_set(rule_set)
      @meta_rule_set = rule_set
    end

    def add_rule_set(rule_set)
      if rule_set.is_a?(Class)
        rule_set = rule_set.instance
      end
      rule_set.rules.each { |r| rules << r }
    end

    def wrap_translate(translate_block, constraints)
      if constraints.any?
        proc do |**kws|
          constraints.each_pair do |var, const|
            raise Transformer::NotApplicable unless RuleSet.validate_constraint(kws[var], const)
          end
          translate_block.(**kws)
        end
      else
        translate_block
      end
    end

    def self.validate_constraint(x, c)
      if c.is_a?(Module)
        x.is_a?(c)
      elsif c.is_a?(Array) && c.size == 1
        return false unless x.is_a?(Array) || x.is_a?(Hash)
        vs = x.is_a?(Array) ? x : x.values
        vs.all? { |v| validate_constraint(v, c[0]) }
      elsif c.is_a?(Array)
        c.any? { |c| validate_constraint(x, c) }
      elsif c.respond_to?(:call)
        c.(x)
      end
    end

    def as_array(x)
      if x.is_a?(Array)
        x
      else
        [x]
      end
    end

    def node_to_pattern(node)
      if !node.is_a?(Parser::AST::Node)
        node
      else
        try_read_var(node) || try_read_splat(node) || try_read_lvasgn(node) ||
            just_node_to_pattern(node)
      end
    end

    def just_node_to_pattern(node)
      n(node.type, node.children.map { |c| node_to_pattern(c) })
    end

    def try_read_var(node)
      cp = Compiler.compile(any(n(:send, [nil, v(:name)]), n(:lvar, [v(:name)])))
      e = cp.match(node)
      if e
        puts "successfully matched var #{node}" if DEBUG
        Var.new(e[:name])
      else
        puts "failed to match var #{node}" if DEBUG
        nil
      end
    end

    def try_read_splat(node)
      cp = Compiler.compile(n(:splat, [any(n(:send, [nil, v(:name)]), n(:lvar, [v(:name)]))]))
      e = cp.match(node)
      if e
        puts "successfully matched splat #{node}" if DEBUG
        Splat.new(e[:name])
      else
        puts "failed to match splat #{node}" if DEBUG
        nil
      end
    end

    def try_read_lvasgn(node)
      cp = Compiler.compile(n(:lvasgn, [v(:lvar), v(:expr)]))
      e = cp.match(node)
      if e
        puts "successfully matched lvasgn #{node}" if DEBUG
        just_node_to_pattern(node.updated(nil, [Var.new(e[:lvar]), node_to_pattern(e[:expr])]))
      else
        puts "failed to match lvasgn #{node}" if DEBUG
        nil
      end
    end
  end
end
