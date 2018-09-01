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
      proc_num = 0
      last_invalid_pattern_error = nil
      last_node = nil
      begin
        file_path, line = *p.source_location
        ast = get_ast(file_path)
        node = find_proc(ast, line, proc_num)
        if node
          last_node = node
          sexp = node_to_sexp(node, p.binding)
          retval = try_to_use ? try_to_use.(sexp) : sexp # If this throws InvalidPattern...
        end
      rescue InvalidPattern => e
        # ... there might be multiple procs/blocks on the same line, e.g.,
        # destructure(...) { ... match { pattern } ...}
        # Look for the next one. If try_to_use doesn't raise, then we'll keep it.
        last_invalid_pattern_error = e
        proc_num += 1
        retry
      end

      if retval
        # cache it
        @sexps_by_proc[p] = retval
      else
        raise InvalidPattern.new(last_invalid_pattern_error.pattern, Unparser.unparse(last_node))
      end
    end

    private

    def get_ast(file_path)
      @asts_by_file.fetch(file_path) do
        @asts_by_file[file_path] = Parser::CurrentRuby.parse(File.read(file_path))
      end
    end

    def find_proc(node, line, proc_num=0)
      return nil unless node.is_a?(Parser::AST::Node)
      is_match = node.type == :block && node.location.line == line
      if is_match && proc_num == 0
        return node.children[2]
      end
      if is_match
        proc_num -= 1
      end
      node.children.lazy.map { |c| find_proc(c, line, proc_num) }.reject(&:nil?).first
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
