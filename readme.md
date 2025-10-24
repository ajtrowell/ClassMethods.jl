# StructMethods.jl

Inspired by experiments from  
https://www.functionalnoise.com/pages/2023-01-31-julia-class/

## Usage

```julia
using StructMethods

@class mutable struct MyClass
    value::Int

    function describe(self::MyClass)
        return "MyClass($(self.value))"
    end

    function set_value!(self::MyClass, new_value::Int)
        self.value = new_value
        return self
    end
end
```

The macro rewrites the struct so that every method whose first argument is typed as the enclosing struct:

- remains available as a regular method (e.g. `MyClass.describe`),
- gets a matching `const` function field stored on each instance,
- is wrapped by an inner constructor-generated closure so the instance can call `obj.describe(...)`.

It also injects an optional `Base.show(io, obj::MyClass)` overload that prints the data fields while avoiding recursion; delete that method if you prefer the default `show`.

## Constructors

`@class` owns the canonical inner constructor so that it can wire up the method fields consistently. User-written inner constructors are therefore rejected. If you need alternative construction paths, define **outer constructors** that forward into the generated one:

```julia
MyClass(str::AbstractString) = MyClass(parse(Int, str))

function MyClass(; value::Int = 0, offset::Int = 0)
    obj = MyClass(value + offset)
    # perform any extra setup or validation here if needed
    return obj
end
```

Outer constructors can perform arbitrary validation, parameter juggling, or conversion before returning the instance created by the macro’s inner constructor.

## Limitations

- Only functions declared inside the struct with a first argument typed exactly as the struct (e.g. `foo(self::MyClass, ...)`) are treated as methods; other definitions remain untouched.
- Parametric structs, unions, or typed aliases for the first argument are not supported yet.
- Additional metaprogramming inside the struct body (e.g. other macros that generate method definitions) may need manual adaptation.

See `examples/macro_MyClass.jl` for a runnable REPL demo and `examples/vanilla_MyClass.jl` for the equivalent hand-written version the macro emulates.


