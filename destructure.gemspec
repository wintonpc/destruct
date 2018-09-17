
Gem::Specification.new do |s|
  s.name        = 'destructure'
  s.version     = '0.2.0'
  s.date        = '2018-09-01'
  s.summary     = 'Destructuring assignment in Ruby'
  s.description = s.summary
  s.authors     = ['Peter Winton']
  #s.email       = ''
  s.files       = ['lib/destructure.rb', *Dir.glob('lib/destructure/*.rb')]
  s.homepage    = 'http://rubygems.org/gems/destructure'
  s.license     = 'MIT'


  s.add_dependency('activesupport', ['> 4.0.0'])
  s.add_dependency('parser')
  s.add_dependency('unparser')

  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'memory_profiler'
end
