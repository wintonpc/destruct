- todo
  - explore unification ('martelli-montanari')
  - error messages with paths
  - avoid mutating the caller (adding instance variables, etc.) as much as possible
  - switch to RSpec expectations

- examples
  - regex
  - ruby array deconstruction
  - rails routes
  - motivation: java -> ruby translator
    - regex example. ok, but unrealistic. works only for strings, not structures
    - show with parse tree input (to_sexp)

- wishlist
  - Destructure matchers should be available in dbind
    - giving up on this. it's possible for Obj and Var, but not for
      Pred because of nested blocks/lambdas. It's really only useful for
      Preds anyway.
  - lambda predicates
    - giving up on this temporarily due to sourcify issues
