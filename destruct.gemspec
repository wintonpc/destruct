
Gem::Specification.new do |s|
  s.name        = 'destruct'
  s.version     = '0.2.0'
  s.date        = '2018-09-01'
  s.summary     = 'Destructuring assignment in Ruby'
  s.description = s.summary
  s.authors     = ['Peter Winton']
  #s.email       = ''
  s.files       = ['lib/destruct.rb', *Dir.glob('lib/destruct/*.rb'), *Dir.glob('ext/destruct_ext/*.{h,c,rb}')]
  s.homepage    = 'http://rubygems.org/gems/destructure'
  s.license     = 'MIT'


  s.add_dependency('activesupport', ['> 4.0.0'])
  s.add_dependency('parser')
  s.add_dependency('unparser')
  s.add_dependency('binding_of_caller')

  s.extensions << 'ext/destruct_ext/extconf.rb'
  s.add_development_dependency 'rake-compiler', '~> 0'
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'memory_profiler'
end
