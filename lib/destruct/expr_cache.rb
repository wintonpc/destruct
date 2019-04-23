# frozen_string_literal: true

require 'parser/current'
require 'unparser'

class Destruct
  # Obtains the AST node for a given proc
  class ExprCache
    class << self
      def instance
        Thread.current[:syntax_cache_instance] ||= ExprCache.new
      end

      def get(p, &k)
        instance.get(p, &k)
      end
    end

    Region = Struct.new(:path, :begin_line, :begin_col, :end_line, :end_col)

    def initialize
      @asts_by_file = {}
      @exprs_by_proc = {}
    end

    # Obtains the AST node for a given proc. The node is found by using
    # Proc#source_location to reparse the source file and find the proc's node
    # on the appropriate line. If there are multiple procs on the same line,
    # procs and lambdas are preferred over blocks, and the first is returned.
    # If try_to_use is provided, candidate nodes are passed to the block for
    # evaluation. If the node is unacceptable, the block is expected to raise
    # InvalidPattern. The first acceptable block is returned.
    # If the proc was entered at the repl, we attempt to find it in the repl
    # history.
    # TODO: Use Region.begin_col to disambiguate. It's not straightforward:
    # Ruby's parser sometimes disagrees with the parser gem. The relative
    # order of multiple procs on the same line should be identical though.
    def get(p, &try_to_use)
      cache_key = p.source_location_id
      sexp = @exprs_by_proc[cache_key]
      return sexp if sexp

      ast, region = get_ast(Region.new(*p.source_region))
      candidate_nodes = find_proc(ast, region)
      # prefer lambdas and procs over blocks
      candidate_nodes = candidate_nodes.sort_by do |n|
        n.children[0].type == :send && (n.children[0].children[1] == :lambda ||
            n.children[0].children[1] == :proc) ? 0 : 1
      end.map { |n| n.children[2] }

      if !try_to_use
        @exprs_by_proc[cache_key] =
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
          @exprs_by_proc[cache_key] = candidate_nodes[first_good_idx]
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

    def get_ast(region)
      if in_repl(region.path)
        start_offset = -1
        old_stderr = $stderr
        begin
          $stderr = File.open(IO::NULL, "w") # silence parse diagnostics
          code = Readline::HISTORY.to_a[start_offset..-1].join("\n")
          [Parser::CurrentRuby.parse(code), Region.new(region.path, 1, 0, 1, 0)]
        rescue Parser::SyntaxError
          start_offset -= 1
          retry
        ensure
          $stderr = old_stderr
        end
      else
        ast = @asts_by_file.fetch(region.path) do
          puts "Parser::CurrentRuby.parse(File.read(#{region.path}))"
          puts "region = #{region}"
          path = region.path
          code =
              if path.is_a?(Array) && File.basename(path.first, ".rb") =~ /boot(\d+)?/
                $boot_code.fetch(File.basename(path.first, ".rb"))
              else
                File.read(path)
              end
          @asts_by_file[path] = Parser::CurrentRuby.parse(code)
        end
        [ast, region]
      end
    end

    def in_repl(file_path)
      file_path == "(irb)" || file_path == "(pry)"
    end

    def find_proc(node, region)
      return [] unless node.is_a?(Parser::AST::Node)
      result = []
      is_match = node.type == :block && node.location.begin.line == region.begin_line
      result << node if is_match
      result += node.children.flat_map { |c| find_proc(c, region) }.reject(&:nil?)
      result
    end
  end
end
