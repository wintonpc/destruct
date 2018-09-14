# frozen_string_literal: true

require 'active_support/core_ext/object/deep_dup'
require 'destruct/types'
require_relative './compiler'

class Destruct
  class Transformer
    DEBUG = true
    Rec = Struct.new(:input, :output, :subs)

    class << self
      def transform(x, rule_set, binding)
        txr = Transformer.new(rule_set, binding)
        result = txr.transform(x)
        dump_rec(txr.last_rec) if DEBUG
        result
      end

      def dump_rec(rec, depth=0)
        return if rec.input == rec.output && rec.subs.none?
        indent = "│  " * depth
        puts "#{indent}┌ #{format(rec.input)}"
        rec.subs.each { |s| dump_rec(s, depth + 1) }
        puts "#{indent}└ #{format(rec.output)}"
      end

      def format(x)
        if x.is_a?(Parser::AST::Node)
          x.to_s.gsub(/\s+/, " ")
        else
          x.inspect
        end
      end
    end

    attr_reader :last_rec

    def initialize(rule_set, binding)
      @rules = rule_set.rules
      @binding = binding
      @rec_stack = []
    end

    def push_rec(input)
      parent = @rec_stack.last
      current = Rec.new(input, nil, [])
      @rec_stack.push(current)
      parent.subs << current if parent
    end

    def pop_rec(output)
      current = @rec_stack.last
      current.output = output
      @rec_stack.pop
      @last_rec = current
      output
    end

    def transform(x)
      push_rec(x)
      if x.is_a?(Array)
        pop_rec(x.map { |v| transform(v) })
      elsif x.is_a?(Hash)
        pop_rec(x.map { |k, v| [transform(k), transform(v)] }.to_h)
      else
        @rules.each do |rule|
          begin
            if rule.pat.is_a?(Class) && x.is_a?(rule.pat)
              return pop_rec(transform(apply_template(rule, x, binding: @binding)))
            elsif e = Compiler.compile(rule.pat).match(x)
              args = {binding: @binding}
              if e.is_a?(Env)
                e.env_each do |k, v|
                  val = v == x ? v : transform(v) # don't try to transform if we know we won't get anywhere (prevent stack overflow); template might guard by raising NotApplicable
                  args[k] = val
                end
              end
              return pop_rec(transform(apply_template(rule, **args)))
            end
          rescue NotApplicable
            # continue to next rule
          end
        end
        pop_rec(x)
      end
    rescue
      pop_rec("<error>")
      raise
    end

    def log(expr, result)
      puts "TX: #{expr.to_s.gsub("\n", " ").gsub(/\s{2,}/, " ")}\n => #{result.to_s.gsub("\n", " ").gsub(/\s{2,}/, " ")}" if DEBUG && expr != result
      result
    end

    def apply_template(rule, *args, **kws)
      if kws.any?
        if !rule.template.parameters.include?([:key, :binding]) && !rule.template.parameters.include?([:keyreq, :binding])
          kws = kws.dup
          kws.delete(:binding)
        end
        rule.template.(*args, **kws)
      else
        rule.template.(*args)
      end
    end


    LITERAL_TYPES = %i[int sym float str].freeze
    class NotApplicable < RuntimeError
    end

    Rule = Struct.new(:pat, :template)

    Code = Struct.new(:code)
    class Code
      def to_s
        "#<Code: #{code}>"
      end
      alias_method :inspect, :to_s
    end

    def self.from(base, &add_rules)
      t = new(base.rules)
      t.instance_exec(&add_rules) if add_rules
      t
    end

    def transform_pattern_proc(*args, &block)
      Context.new(@rules).transform_pattern_proc(*args, &block)
    end

    module Methods
      def n(type, children=[])
        Obj.new(Parser::AST::Node, type: type, children: children)
      end

      def v(name)
        Var.new(name)
      end

      def s(name)
        Splat.new(name)
      end

      def any(*alt_patterns)
        Or.new(*alt_patterns)
      end

      def quote(&block)
        quo(ExprCache.get(block), block.binding, block.source_location[0])
      end

      def quo(n, binding, file)
        if !n.is_a?(Parser::AST::Node)
          n
        elsif n.type == :send && n.children[1] == :!
          expr = n.children[0]
          line = expr.location.line
          binding.eval(Unparser.unparse(expr), file, line)
        else
          n.updated(nil, n.children.map { |c| quo(c, binding, file) })
        end
      end

      class << self
        def unparse(x)
          if x.is_a?(Code)
            x.code
          elsif x.is_a?(Parser::AST::Node)
            Unparser.unparse(x)
          elsif x.is_a?(Var)
            x.name.to_s
          else
            x
          end
        end
      end
    end

    include Methods

    class Context
      include Methods

      def initialize(rules=[])
        @rules = rules
      end

      NOTHING = Object.new

      def transform_pattern_proc(&pat_proc)
        transform(NOTHING, 0, pat_proc.binding, on_unmatched: :ignore, &pat_proc)
      end


    end
  end
end

def quote(&block)
  Destruct::Transformer::Identity.quote(&block)
end
