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

      file_path, line = *p.source_location
      ast = get_ast(file_path)
      candidate_nodes = find_proc(ast, line)

      if !try_to_use
        @exprs_by_proc[p] = candidate_nodes.first
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

    def get_ast(file_path)
      @asts_by_file.fetch(file_path) do
        @asts_by_file[file_path] = Parser::CurrentRuby.parse(File.read(file_path))
      end
    end

    def find_proc(node, line)
      return [] unless node.is_a?(Parser::AST::Node)
      result = []
      is_match = node.type == :block && node.location.line == line
      result << node.children[2] if is_match
      result += node.children.flat_map { |c| find_proc(c, line) }.reject(&:nil?)
      result
    end
  end
end
