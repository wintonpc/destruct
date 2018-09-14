require 'destruct'

class Destruct
  module TransformerHelpers
    def given_rule(*args, &block)
      @transformer = Transformer.from(Transformer::PatternBase) do
        add_rule(*args, &block)
      end
    end

    def transform(&pat_proc)
      @rule_set.transform(&pat_proc)
    end

    def given_pattern(&pat_proc)
      @pat_proc = pat_proc
    end

    def match(x, pat_proc)
      cp = Compiler.compile(transform(&pat_proc))
      cp.match(x)
    end

    def given_binding(binding)
      @binding = binding
    end

    def expect_success_on(x, bindings={})
      @rule_set ||= RuleSets::PatternBase
      env = Compiler.compile(transform(&@pat_proc)).match(x, @binding)
      expect(env).to be_truthy
      bindings.each do |k, v|
        expect(env[k]).to eql v
      end
    end

    def expect_failure_on(x)
      @rule_set ||= RuleSets::PatternBase
      env = Compiler.compile(transform(&@pat_proc)).match(x, @binding)
      expect(env).to be_falsey
    end
  end
end
