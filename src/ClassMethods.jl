module ClassMethods

export @class

struct MethodSpec
    name::Symbol
    expr::Any
end

struct FieldSpec
    name::Symbol
    signature_arg::Any
    expr::Any
end

function _is_line(node)
    return node isa LineNumberNode
end

function _extract_field(stmt)
    if stmt isa Symbol
        name = stmt
        signature = stmt
        return FieldSpec(name, signature, stmt)
    elseif stmt isa Expr && stmt.head == :(::)
        name = stmt.args[1]
        signature = Expr(:(::), name, stmt.args[2])
        return FieldSpec(name, signature, stmt)
    else
        return nothing
    end
end

function _method_match_from_call(call_expr, struct_name::Symbol)
    call_expr isa Expr && call_expr.head == :call || return nothing
    length(call_expr.args) >= 2 || return nothing
    arg_index = 2
    if call_expr.args[arg_index] isa Expr && call_expr.args[arg_index].head == :parameters
        arg_index += 1
        arg_index <= length(call_expr.args) || return nothing
    end
    first_arg = call_expr.args[arg_index]
    first_arg isa Expr && first_arg.head == :(::) || return nothing
    first_arg_type = first_arg.args[2]
    first_arg_type == struct_name || return nothing
    method_name = call_expr.args[1]
    method_name isa Symbol || return nothing
    return method_name
end

function _maybe_method(stmt, struct_name::Symbol)
    if stmt isa Expr && stmt.head == :function
        signature = stmt.args[1]
        if signature isa Expr && signature.head == :call && signature.args[1] == struct_name
            error("`@class` does not support manually defined inner constructors; remove the constructor or define it outside the struct.")
        end
        method_name = _method_match_from_call(signature, struct_name)
        if method_name === nothing
            return nothing
        end
        return MethodSpec(method_name, stmt)
    elseif stmt isa Expr && stmt.head == :(=)
        lhs = stmt.args[1]
        lhs isa Expr && lhs.head == :call || return nothing
        lhs.args[1] == struct_name && error("`@class` does not support manually defined inner constructors; remove the constructor or define it outside the struct.")
        method_name = _method_match_from_call(lhs, struct_name)
        if method_name === nothing
            return nothing
        end
        return MethodSpec(method_name, stmt)
    else
        return nothing
    end
end

function _make_const_field_expr(method_name::Symbol)
    inner = Expr(:(::), method_name, :Function)
    return Expr(:const, inner)
end

function _make_method_closure_expr(method_name::Symbol)
    kw_tuple = Expr(:parameters, Expr(:..., :kwargs))
    arg_tuple = Expr(:tuple, kw_tuple, Expr(:..., :args))
    call_expr = Expr(:call, method_name, kw_tuple, :obj, Expr(:..., :args))
    return Expr(:->, arg_tuple, call_expr)
end

function _build_constructor(struct_name::Symbol, field_specs::Vector{FieldSpec}, methods::Vector{MethodSpec})
    signature_args = [spec.signature_arg for spec in field_specs]
    constructor_signature = Expr(:call, struct_name, signature_args...)

    field_names = [spec.name for spec in field_specs]
    closures = [_make_method_closure_expr(method.name) for method in methods]
    new_args = vcat(field_names, closures)

    assign_expr = Expr(:(=), :obj, Expr(:call, :new, new_args...))
    return_expr = :(return obj)
    body = Expr(:block, assign_expr, return_expr)
    return Expr(:function, constructor_signature, body)
end

macro class(ex)
    ex isa Expr && ex.head == :struct || error("@class must wrap a struct definition")
    is_mutable = ex.args[1]
    struct_name = ex.args[2]
    struct_name isa Symbol || error("@class only supports non-parametric structs")
    body_expr = ex.args[3]
    body_expr isa Expr && body_expr.head == :block || error("struct body must be a block")

    fields = FieldSpec[]
    field_stmts = Any[]
    method_specs = MethodSpec[]
    method_stmts = Any[]
    other_stmts = Any[]
    pending_lines = Any[]

    for stmt in body_expr.args
        if _is_line(stmt)
            push!(pending_lines, stmt)
            continue
        end

        fieldspec = _extract_field(stmt)
        if fieldspec !== nothing
            append!(field_stmts, pending_lines)
            empty!(pending_lines)
            push!(field_stmts, stmt)
            push!(fields, fieldspec)
            continue
        end

        methodspec = _maybe_method(stmt, struct_name)
        if methodspec !== nothing
            append!(method_stmts, pending_lines)
            empty!(pending_lines)
            push!(method_stmts, methodspec.expr)
            push!(method_specs, methodspec)
            continue
        end

        append!(other_stmts, pending_lines)
        empty!(pending_lines)
        push!(other_stmts, stmt)
    end

    if !isempty(pending_lines)
        append!(other_stmts, pending_lines)
    end

    isempty(fields) && error("@class requires at least one non-method field")

    method_names = Symbol[]
    for method in method_specs
        if method.name in method_names
            error("Duplicate method definition for $(method.name)")
        end
        push!(method_names, method.name)
    end

    const_fields = [_make_const_field_expr(name) for name in method_names]
    constructor_expr = _build_constructor(struct_name, fields, method_specs)

    new_body_items = Any[]
    append!(new_body_items, field_stmts)
    append!(new_body_items, const_fields)
    append!(new_body_items, method_stmts)
    append!(new_body_items, other_stmts)
    push!(new_body_items, constructor_expr)

    new_body = Expr(:block, new_body_items...)
    new_struct = Expr(:struct, is_mutable, struct_name, new_body)
    return esc(new_struct)
end

end # module ClassMethods
