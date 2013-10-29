- todo
  - error messages with paths
  - avoid mutating the caller (adding instance variables, etc.) as much as possible

- examples
  - regex
  - ruby array destructuring
  - rails routes
  - motivation: java -> ruby translator
    - regex example. ok, but unrealistic. works only for strings, not structures
    - show with parse tree input (to_sexp)

- motivations
  - (x) variable parameter lists
  - (x) testing
  - (x) static analysis
    - destructure: sexp matching
  - convert notification handling

- wishlist
  - Destructure matchers should be available in dbind
    - giving up on this. it's possible for Obj and Var, but not for
      Pred because of nested blocks/lambdas. It's really only useful for
      Preds anyway.
  - lambda predicates
    - giving up on this temporarily due to sourcify issues
  - explore unification ('martelli-montanari')
    - don't think we need/want this