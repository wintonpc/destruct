# frozen_string_literal: true

require 'parser/current'
require 'unparser'

class DMatch
  class ProcSexps
    class << self
      def instance
        Thread.current[:proc_sexps_instance] ||= ProcSexps.new
      end

      def get(p, &k)
        instance.get(p, &k)
      end
    end

    def initialize
      @asts_by_file = {}
      @sexps_by_proc = {}
    end

    def get(p, &try_to_use)
      # return it if we have it
      retval = @sexps_by_proc[p]
      return retval if retval

      # go find it
      file_path, line = *p.source_location
      ast = get_ast(file_path)
      candidate_nodes = find_proc(ast, line)
      to_s
      retval =
          if try_to_use
            mapped_candidates = candidate_nodes.map do |n|
              begin
                try_to_use.(node_to_sexp(n, p.binding))
              rescue InvalidPattern => e
                e
              end
            end
            selected = mapped_candidates.reject { |x| x.is_a?(InvalidPattern) }.first
            selected or raise InvalidPattern.new(mapped_candidates.last.pattern, Unparser.unparse(candidate_nodes.last))
          else
            node_to_sexp(candidate_nodes.first, p.binding)
          end

      # cache it
      @sexps_by_proc[p] = retval
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

    def node_to_sexp(n, binding)
      if n.is_a?(Parser::AST::Node)
        if n.type == :dstr
          str = n.children.map do |c|
            if c.type == :str
              c.children[0]
            elsif c.type == :begin
              binding.eval(Unparser.unparse(c))
            end
          end.join
          [:str, str]
        else
          [n.type, *n.children.map { |c| node_to_sexp(c, binding) }]
        end
      else
        n
      end
    end
  end
end
