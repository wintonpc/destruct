Gem::Specification.new do |s|
  s.name        = 'destructure'
  s.version     = '0.0.12'
  s.date        = '2013-11-04'
  s.summary     = 'Destructuring assignment in Ruby'
  s.description = s.summary
  s.authors     = ['Peter Winton']
  #s.email       = ''
  s.files       = ['lib/destructure.rb', *Dir.glob('lib/destructure/*.rb')]
  s.homepage    = 'http://rubygems.org/gems/destructure'
  s.license     = 'MIT'

  s.add_dependency('sourcify', ['~> 0.6.0.rc4'])
  s.add_dependency('activesupport', ['~> 4.0.0'])
  s.add_dependency('binding_of_caller', ['~> 0.7.2'])
  s.add_dependency('paramix', ['~> 2.0.1'])
end