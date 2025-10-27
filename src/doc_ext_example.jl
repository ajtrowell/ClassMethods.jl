using DocStringExtensions: TYPEDFIELDS

export Horse

"""
    Horse

Small example demonstrating `DocStringExtensions.TYPEDFIELDS` for field docs.

$(TYPEDFIELDS)
"""
struct Horse
  "Stable name for the horse."
  name::String
  "Age of the horse in years."
  age::Int
end
