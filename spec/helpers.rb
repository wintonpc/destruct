require 'rspec'
$LOAD_PATH.push File.join(File.dirname(__FILE__), '../lib/destructure')
require 'dmatch'

shared_context 'types' do
  Obj = DMatch::Obj unless defined? Obj
  Env = DMatch::Env unless defined? Env
  Var = DMatch::Var unless defined? Var
  Splat = DMatch::Splat unless defined? Splat
  FilterSplat = DMatch::FilterSplat unless defined? FilterSplat
  SelectSplat = DMatch::SelectSplat unless defined? SelectSplat
  Pred = DMatch::Pred unless defined? Pred
  Or = DMatch::Or unless defined? Or
end

