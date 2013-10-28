require 'destructure/destructure'

class Object
  def =~(pattern_lambda)
    if pattern_lambda.is_a?(Proc)
      caller_binding = binding.of_caller(1)
      caller_location = caller_locations(1,1)[0].label
      caller = caller_binding.eval('self')
      caller.class.send(:include, Destructure) unless caller.class.included_modules.include?(Destructure)
      caller.send(:dbind_internal, self, pattern_lambda.to_sexp, caller_binding, caller_location)
    else
      super
    end
  end
end

class String

  orig = instance_method(:=~)

  define_method(:=~) do |pattern_lambda|
    if pattern_lambda.is_a?(Regexp)
      orig.bind(self).call(pattern_lambda)
    else
      # stuff gets cranky if you try to factor this out
      caller_binding = binding.of_caller(1)
      caller_location = caller_locations(1,1)[0].label
      caller = caller_binding.eval('self')
      caller.class.send(:include, Destructure) unless caller.class.included_modules.include?(Destructure)
      caller.send(:dbind_internal, self, pattern_lambda.to_sexp, caller_binding, caller_location)
    end
  end
end

class Symbol

  orig = instance_method(:=~)

  define_method(:=~) do |pattern_lambda|
    if pattern_lambda.is_a?(Regexp)
      orig.bind(self).call(pattern_lambda)
    else
      # stuff gets cranky if you try to factor this out
      caller_binding = binding.of_caller(1)
      caller_location = caller_locations(1,1)[0].label
      caller = caller_binding.eval('self')
      caller.class.send(:include, Destructure) unless caller.class.included_modules.include?(Destructure)
      caller.send(:dbind_internal, self, pattern_lambda.to_sexp, caller_binding, caller_location)
    end
  end
end