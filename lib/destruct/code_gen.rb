require 'stringio'

class Destruct
  module CodeGen
    def emitted
      @emitted ||= StringIO.new
    end

    def emit(str)
      emitted << str
      emitted << "\n"
    end

    def generate
      code = <<~CODE
        lambda do |_code, _refs#{ref_args}|
          #{emitted.string}
        end
      CODE
      code = beautify_ruby(code)
      # show_code(code, refs, fancy: true, include_vm: false)
      begin
        eval(code).call(code, refs, *refs.values)
      rescue SyntaxError
        show_code(code, refs, fancy: true, include_vm: false)
        raise
      end
    end

    def show_code_on_error(&emit_inner_code)
      emit_begin emit_body: emit_inner_code, emit_rescues: (proc do
        emit <<~RESCUE
        rescue
          ::Destruct::CodeGen.show_code(_code, _refs)
          raise
        RESCUE
      end)
    end

    def emit_begin(emit_body:, emit_rescues: nil)
      emit "begin"
      emit_body.call
      emit_rescues&.call
      emit "end"
    end

    def emit_lambda(*args, &emit_body)
      emit "lambda do |#{args.join(", ")}|"
      emit_body.call
      emit "end"
    end

    private def ref_args
      return "" if refs.none?
      ", \n#{refs.map { |k, v| "#{k.to_s.ljust(8)}, # #{v.inspect}" }.join("\n")}\n"
    end

    def beautify_ruby(code)
      RBeautify.beautify_string(code.split("\n").reject { |line| line.strip == '' }).first
    end

    def refs
      @refs ||= {}
    end

    def reverse_refs
      @reverse_refs ||= {}
    end

    def get_ref(value, id=nil)
      reverse_refs.fetch(value) do
        if id
          raise "ref #{id} is already bound" if refs.keys.include?(id)
        else
          id = get_temp
        end
        refs[id] = value
        reverse_refs[value] = id
        id
      end
    end

    def get_temp(prefix="t")
      @temp_num ||= 0
      "_#{prefix}#{@temp_num += 1}"
    end

    module_function

    def show_code(code, refs, fancy: true, include_vm: false)
      lines = number_lines(code)
      if fancy
        lines = lines
                    .reject { |line| line =~ /^\s*\d+\s*puts/ }
                    .map do |line|
          if line !~ /, #|_code|_refs/
            refs.each do |k, v|
              line = line.gsub(/#{k}(?!\d+)/, v.inspect)
            end
          end
          line
        end
      end
      puts lines
      if include_vm
        pp RubyVM::InstructionSequence.compile(code).to_a
      end
    end

    def number_lines(code)
      code.split("\n").each_with_index.map do |line, n|
        "#{(n + 1).to_s.rjust(3)} #{line}"
      end
    end
  end
end
