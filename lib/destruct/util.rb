def make_singleton(inspect_str)
  obj = Object.new
  obj.define_singleton_method(:to_s) { inspect_str }
  obj.define_singleton_method(:inspect) { inspect_str }
  obj
end
