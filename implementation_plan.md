Implementation Plan
-------------------
- Replace the placeholder contents of `src/StructMethods.jl` with the `@structmethods` macro machinery, including helper functions to parse the struct body, collect field declarations, and detect method blocks whose first argument is annotated as the enclosing struct type.
- Support both long-form `function f(self::ThisType, ...) ... end` definitions and short-form assignments `f(self::ThisType, ...) = ...` inside the struct block by normalizing them into a common representation.
- For each detected method, emit a `const` function-typed field in the struct definition and extend the method definition so it remains available outside the struct body.
- Synthesize an inner constructor that instantiates the struct, then assigns each method field a closure wrapping the corresponding function, e.g. `(args...; kwargs...) -> method(obj, args...; kwargs...)`.
- Update or add example usages/tests (e.g., `examples/macro_MyClass.jl`) to validate the macro and ensure it mirrors the vanilla hand-written pattern.
- Preserve docstrings by threading original literals through expansion, wrapping the rewritten struct in `Base.@__doc__`, and re-emitting method docstrings so Julia's docsystem (and tools like `DocStringExtensions.FIELDS`) retain field/method metadata.

Limitations
-----------
- Only method definitions whose first argument is explicitly annotated as the enclosing struct type (e.g., `self::MyClass`) are recognised; untyped arguments, unions, abstract supertypes, parametric forms, or destructuring patterns are ignored.
- Constructors supplied manually inside the struct body are not automatically merged with the generated inner constructor; such combinations will need to be forbidden or handled case-by-case.
- Macro relies on syntactic structure present at expansion time; wrapping method definitions in other macros or metaprogramming constructs is out of scope.

Open Questions
--------------
- None at this time.
