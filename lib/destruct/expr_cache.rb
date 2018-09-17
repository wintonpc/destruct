# frozen_string_literal: true

require 'parser/current'
require 'unparser'

class Destruct
  class ExprCache
    class << self
      def instance
        Thread.current[:syntax_cache_instance] ||= ExprCache.new
      end

      def get(p, &k)
        instance.get(p, &k)
      end
    end

    def initialize
      @asts_by_file = {}
      @exprs_by_proc = {}
    end

    def get(p, &try_to_use)
      sexp = @exprs_by_proc[p]
      return sexp if sexp

      ast, line = get_ast(*p.source_location)
      candidate_nodes = find_proc(ast, line)
      candidate_nodes = candidate_nodes.sort_by do |n|
        n.children[0].type == :send && (n.children[0].children[1] == :lambda ||
            n.children[0].children[1] == :proc) ? 0 : 1
      end.map { |n| n.children[2] }

      if !try_to_use
        @exprs_by_proc[p] =
            if candidate_nodes.size > 1
              candidate_nodes.reject { |n| contains_block?(n) }.first # hack to deal with more than one per line
            else
              candidate_nodes.first
            end
      else
        tried_candidates = candidate_nodes.map do |n|
          begin
            try_to_use.(n)
          rescue InvalidPattern => e
            e
          end
        end
        first_good_idx = tried_candidates.find_index { |x| !x.is_a?(InvalidPattern) }
        if first_good_idx
          @exprs_by_proc[p] = candidate_nodes[first_good_idx]
          tried_candidates[first_good_idx]
        else
          raise InvalidPattern.new(tried_candidates.last.pattern, Unparser.unparse(candidate_nodes.last))
        end
      end
    end

    private

    def contains_block?(node)
      if !node.is_a?(Parser::AST::Node)
        false
      elsif node.type == :block
        true
      else
        node.children.any? { |c| contains_block?(c) }
      end
    end

    def get_ast(file_path, line)
      if in_repl(file_path)
        start_offset = -1
        begin
          $silence_parser_diagnostics = true
          code = Readline::HISTORY.to_a[start_offset..-1].join("\n")
          [Parser::CurrentRuby.parse(code), 1]
        rescue Parser::SyntaxError
          start_offset -= 1
          retry
        ensure
          $silence_parser_diagnostics = false
        end
      else
        ast = @asts_by_file.fetch(file_path) do
          @asts_by_file[file_path] = Parser::CurrentRuby.parse(File.read(file_path))
        end
        [ast, line]
      end
    end

    def in_repl(file_path)
      file_path == "(irb)" || file_path == "(pry)"
    end

    def find_proc(node, line)
      return [] unless node.is_a?(Parser::AST::Node)
      result = []
      is_match = node.type == :block && node.location.line == line
      result << node if is_match
      result += node.children.flat_map { |c| find_proc(c, line) }.reject(&:nil?)
      result
    end
  end
end

require 'parser/runner'

module Kernel
  old_puts = instance_method(:puts)
  define_method(:puts) do |*args|
    old_puts.bind(self).(caller)
    old_puts.bind(self).(*args)
  end
end

module Parser
  class Runner
    old_prepare_parser = instance_method(:prepare_parser)
    define_method(:prepare_parser) do
      if $silence_parser_diagnostics
        @parser = @parser_class.new
      else
        old_prepare_parser.bind(self).call
      end
    end
  end
end
