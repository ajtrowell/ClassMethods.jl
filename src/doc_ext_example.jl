using Base: @kwdef
using DocStringExtensions: TYPEDFIELDS

export Horse

"""
    Horse

Small example demonstrating `DocStringExtensions.TYPEDFIELDS` for field docs.

$(TYPEDFIELDS)
"""
@kwdef struct Horse
  "Stable name for the horse."
  name::String = "Unnamed"
  "Age of the horse in years."
  age::Int = 0
end
