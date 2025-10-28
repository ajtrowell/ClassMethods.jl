# StructMethods.jl

Inspired by experiments from  
https://www.functionalnoise.com/pages/2023-01-31-julia-class/

Note more thorough OOP implementation here
https://github.com/Suzhou-Tongyuan/ObjectOriented.jl

## Usage

```julia
using StructMethods

@structmethods mutable struct MyClass
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
- is exposed as a function field on each instance (the generated `setproperty!` prevents reassignment so it behaves like `const`),
- is wrapped by an inner constructor-generated closure so the instance can call `obj.describe(...)`.

It also injects an optional `Base.show(io, obj::MyClass)` overload that prints the data fields while avoiding recursion; delete that method if you prefer the default `show`.

## Supported definitions

- Method blocks:

  ```julia
  function adjust!(self::MyClass, delta::Int; scale::Int = 1) ...
  ```

- Single-expression methods:

  ```julia
  describe(self::MyClass) = "MyClass($(self.value))"
  ```

- Closure syntax via field assignment (handy for short methods):

  ```julia
  reset! = (self::MyClass, value::Int) -> (self.value = value; self)
  ```

Every form above can carry inline docstrings, and those docstrings flow through `DocStringExtensions.FIELDS` and `DocStringExtensions.TYPEDFIELDS`.

`@structmethods` also respects default values introduced with `Base.@kwdef`, so keyword construction works naturally.

## Constructors

`@structmethods` owns the canonical inner constructor so that it can wire up the method fields consistently. User-written inner constructors are therefore rejected. If you need alternative construction paths, define **outer constructors** that forward into the generated one:

```julia
MyClass(str::AbstractString) = MyClass(parse(Int, str))

function MyClass(; value::Int = 0, offset::Int = 0)
    obj = MyClass(value + offset)
    # perform any extra setup or validation here if needed
    return obj
end
```

Outer constructors can perform arbitrary validation, parameter juggling, or conversion before returning the instance created by the macro’s inner constructor.
Attempting to reassign a generated method field raises the same `setfield!: const field … cannot be changed` error you would get from a hand-written `const` slot.

### Field type coercion

Starting with the current release, any field declared with an explicit type annotation (for example `messages::Vector{Int32}`) is coerced inside the generated constructor before `new` is called. This means callers can pass convenient literals such as `[]` or `["1", "2"]` and the macro will apply `convert` to obtain a `Vector{Int32}` (or throw an informative `ArgumentError` if conversion is impossible). The same logic runs for both positional and keyword constructors, so defaults stay ergonomic without sacrificing type safety.

## Limitations

- Only functions declared inside the struct with a first argument typed exactly as the struct (e.g. `foo(self::MyClass, ...)`) are treated as methods; other definitions remain untouched.
- Parametric structs, unions, or typed aliases for the first argument are not supported yet.
- Additional metaprogramming inside the struct body (e.g. other macros that generate method definitions) may need manual adaptation.

See `examples/macro_MyClass.jl` for a runnable REPL demo and `examples/vanilla_MyClass.jl` for the equivalent hand-written version the macro emulates.

## Docstrings and examples

The macro preserves struct field docstrings and captures method docstrings on the generated fields, so abbreviations like `$(FIELDS)` and `$(TYPEDFIELDS)` show both fields and method names.

Below is a minimal “Dog” implementation spelled out manually and then using `@structmethods`.

```julia
using DocStringExtensions: TYPEDFIELDS

"""
    Dog

Fully expanded version without macros.

$(TYPEDFIELDS)
"""
mutable struct Dog
    """Dog name doc"""
    name::String
    """Dog age doc"""
    age::Int
    """Return the age in dog years."""
    dog_years::Function
    describe::Function

    function Dog(name::String, age::Int)
        obj = new(
            name,
            age,
            (args...; kwargs...) -> dog_years(obj, args...; kwargs...),
            (args...; kwargs...) -> describe(obj, args...; kwargs...),
        )
        return obj
    end

    function Dog(; name::String = "Fido", age::Int = 0)
        obj = new(
            name,
            age,
            (args...; kwargs...) -> dog_years(obj, args...; kwargs...),
            (args...; kwargs...) -> describe(obj, args...; kwargs...),
        )
        return obj
    end
end

function Base.setproperty!(dog::Dog, name::Symbol, value)
    if name === :dog_years || name === :describe
        error("setfield!: const field .$name of type Dog cannot be changed")
    end
    return Base.setfield!(dog, name, value)
end

"""
Return the age in dog years.
"""
function dog_years(self::Dog)
    self.age * 7
end

describe(self::Dog) = "Dog($(self.name), $(self.age))"

function Base.show(io::IO, dog::Dog)
    print(io, "Dog($(repr(dog.name)), $(dog.age))")
end
```

The macro version produces equivalent behaviour (including the `setproperty!` guard) without the boilerplate:

```julia
using StructMethods
using DocStringExtensions: TYPEDFIELDS

"""
    Dog

Example using @structmethods.

$(TYPEDFIELDS)
"""
@structmethods mutable struct Dog
    """Dog name doc"""
    name::String = "Fido"

    """Dog age doc"""
    age::Int = 0

    """Return the age in dog years."""
    function dog_years(self::Dog)
        self.age * 7
    end

    describe(self::Dog) = "Dog($(self.name), $(self.age))"
end
```

Both versions expose docstrings through `DocStringExtensions` and offer the same keyword constructor defaults; the macro form additionally rejects reassignment such as `dog.describe = identity`.

## Agent support
Using with
https://github.com/ajtrowell/shared_julia_depot
julia sandboxing.
