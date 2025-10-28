
struct MethodSpec
    name::Symbol
    expr::Any
    doc_exprs::Vector{Any}
end

struct FieldSpec
    name::Symbol
    signature_arg::Any
    expr::Any
    has_default::Bool
    default_expr::Any
end

function _field_type_error(struct_name::Symbol, field_name::Symbol, expected, value)
    msg = "Field $(field_name) of $(struct_name) requires a value of type $(expected); got $(typeof(value))."
    throw(ArgumentError(msg))
end

function _coerce_field(expected, value, field_name::Symbol, struct_name::Symbol)
    if value isa expected
        return value
    end
    converted = try
        convert(expected, value)
    catch err
        if err isa MethodError || err isa ArgumentError || err isa TypeError
            _field_type_error(struct_name, field_name, expected, value)
        else
            rethrow()
        end
    end
    if converted isa expected
        return converted
    end
    _field_type_error(struct_name, field_name, expected, value)
end

function _is_line(node)
    return node isa LineNumberNode
end

function _is_docstring(node)
    if node isa String
        return true
    elseif node isa Expr
        return node.head === :string || node.head === :call ||
            (node.head === :macrocall && node.args[1] === Symbol("@doc_str"))
    else
        return false
    end
end

function _extract_field(stmt, struct_name::Symbol)
    has_default = false
    default_expr = nothing
    field_expr = stmt

    if stmt isa Expr && stmt.head == :(=)
        field_expr = stmt.args[1]
        default_expr = stmt.args[2]
        has_default = true
    end

    if field_expr isa Symbol
        name = field_expr
        signature = field_expr
        clean_expr = field_expr
    elseif field_expr isa Expr && field_expr.head == :(::)
        name = field_expr.args[1]
        signature = Expr(:(::), name, field_expr.args[2])
        clean_expr = field_expr
    else
        return nothing
    end

    if has_default && default_expr isa Expr && default_expr.head == :-> && name isa Symbol
        call_expr = _call_expr_from_arrow(name, default_expr.args[1])
        if call_expr !== nothing && _method_match_from_call(call_expr, struct_name) !== nothing
            return nothing
        end
    end

    return FieldSpec(name, signature, clean_expr, has_default, default_expr)
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

function _call_expr_from_arrow(method_name::Symbol, arg_expr)
    parts = if arg_expr isa Expr && arg_expr.head == :tuple
        arg_expr.args
    elseif arg_expr isa Expr && arg_expr.head == :block
        arg_expr.args
    else
        return nothing
    end

    call_args = Any[method_name]
    positional_args = Any[]
    kw_entries = Any[]
    params_expr = nothing

    for part in parts
        if part isa LineNumberNode
            continue
        elseif part isa Expr && part.head == :parameters
            params_expr === nothing || return nothing
            params_expr = Base.deepcopy(part)
        elseif part isa Expr && part.head == :(=)
            kw = Expr(:kw, part.args[1], Base.deepcopy(part.args[2]))
            push!(kw_entries, kw)
        else
            push!(positional_args, Base.deepcopy(part))
        end
    end

    if !isempty(kw_entries)
        if params_expr === nothing
            params_expr = Expr(:parameters, kw_entries...)
        else
            append!(params_expr.args, kw_entries)
        end
    end

    if params_expr !== nothing
        push!(call_args, params_expr)
    end

    append!(call_args, positional_args)

    if length(call_args) == 1
        return nothing
    end
    return Expr(:call, call_args...)
end

function _maybe_method(stmt, struct_name::Symbol)
    if stmt isa Expr && stmt.head == :function
        signature = stmt.args[1]
        if signature isa Expr && signature.head == :call && signature.args[1] == struct_name
            error("`@structmethods` does not support manually defined inner constructors; remove the constructor or define it outside the struct.")
        end
        method_name = _method_match_from_call(signature, struct_name)
        if method_name === nothing
            return nothing
        end
        return MethodSpec(method_name, stmt, Any[])
    elseif stmt isa Expr && stmt.head == :(=)
        lhs = stmt.args[1]
        rhs = stmt.args[2]
        if lhs isa Expr && lhs.head == :call
            lhs.args[1] == struct_name && error("`@structmethods` does not support manually defined inner constructors; remove the constructor or define it outside the struct.")
            method_name = _method_match_from_call(lhs, struct_name)
            if method_name === nothing
                return nothing
            end
            return MethodSpec(method_name, stmt, Any[])
        elseif lhs isa Symbol && rhs isa Expr && rhs.head == :-> 
            lhs == struct_name && error("`@structmethods` does not support manually defined inner constructors; remove the constructor or define it outside the struct.")
            call_expr = _call_expr_from_arrow(lhs, rhs.args[1])
            if call_expr === nothing
                return nothing
            end
            method_name = _method_match_from_call(call_expr, struct_name)
            if method_name === nothing
                return nothing
            end
            body_expr = Base.deepcopy(rhs.args[2])
            method_expr = Expr(:(=), call_expr, body_expr)
            return MethodSpec(method_name, method_expr, Any[])
        else
            return nothing
        end
    else
        return nothing
    end
end

function _make_method_field_entries(method::MethodSpec)
    entries = Any[]
    for doc in method.doc_exprs
        push!(entries, Base.deepcopy(doc))
    end
    push!(entries, Expr(:(::), method.name, :Function))
    return entries
end

function _make_method_closure_expr(method_name::Symbol)
    kw_tuple = Expr(:parameters, Expr(:..., :kwargs))
    arg_tuple = Expr(:tuple, kw_tuple, Expr(:..., :args))
    call_expr = Expr(:call, method_name, kw_tuple, :obj, Expr(:..., :args))
    return Expr(:->, arg_tuple, call_expr)
end

function _build_setproperty_override(struct_name::Symbol, method_names::Vector{Symbol})
    isempty(method_names) && return nothing

    obj_arg = Expr(:(::), :obj, struct_name)
    name_arg = Expr(:(::), :name, :Symbol)
    value_sym = :value

    guard_expr = nothing
    for method_name in method_names
        eq_expr = Expr(:call, :(===), :name, QuoteNode(method_name))
        guard_expr = guard_expr === nothing ? eq_expr : Expr(:||, guard_expr, eq_expr)
    end

    guard_expr === nothing && return nothing

    struct_name_str = string(struct_name)
    error_msg = Expr(:call, :string,
        "setfield!: const field .",
        :name,
        " of type ",
        struct_name_str,
        " cannot be changed",
    )
    error_call = Expr(:call, :error, error_msg)
    setfield_call = Expr(:call, :(Base.setfield!), :obj, :name, value_sym)
    body = Expr(:block, Expr(:if, guard_expr, error_call), setfield_call)
    fn_head = Expr(:call, :(Base.setproperty!), obj_arg, name_arg, value_sym)
    return Expr(:function, fn_head, body)
end

function _build_constructors(struct_name::Symbol, field_specs::Vector{FieldSpec}, methods::Vector{MethodSpec})
    signature_args = [spec.name for spec in field_specs]
    field_names = [spec.name for spec in field_specs]
    closures = [_make_method_closure_expr(method.name) for method in methods]
    new_args = vcat(field_names, closures)

    coercion_stmts = Any[]
    coerce_ref = GlobalRef(@__MODULE__, Symbol("_coerce_field"))
    for spec in field_specs
        signature = spec.signature_arg
        if signature isa Expr && signature.head == :(::)
            field_type = Base.deepcopy(signature.args[2])
            field_name = spec.name
            coerce_call = Expr(
                :call,
                coerce_ref,
                field_type,
                field_name,
                QuoteNode(field_name),
                QuoteNode(struct_name),
            )
            push!(coercion_stmts, Expr(:(=), field_name, coerce_call))
        end
    end

    assign_expr = Expr(:(=), :obj, Expr(:call, :new, new_args...))
    return_expr = :(return obj)
    body_items = Any[]
    append!(body_items, coercion_stmts)
    push!(body_items, assign_expr)
    push!(body_items, return_expr)
    body = Expr(:block, body_items...)

    positional_signature = Expr(:call, struct_name, signature_args...)
    positional_constructor = Expr(:function, positional_signature, body)

    kw_params = Any[]
    for spec in field_specs
        if spec.has_default
            push!(kw_params, Expr(:kw, spec.name, Base.deepcopy(spec.default_expr)))
        else
            push!(kw_params, spec.name)
        end
    end

    kw_signature = if isempty(kw_params)
        Expr(:call, struct_name, Expr(:parameters))
    else
        Expr(:call, struct_name, Expr(:parameters, kw_params...))
    end
    kw_constructor = Expr(:function, kw_signature, body)

    return Any[positional_constructor, kw_constructor]
end

function _build_show_definition(struct_name::Symbol, field_specs::Vector{FieldSpec})
    io_arg = Expr(:(::), :io, :IO)
    obj_arg = Expr(:(::), :obj, struct_name)
    call_head = Expr(:call, :(Base.show), io_arg, obj_arg)

    body_items = Any[]
    push!(body_items, :(print(io, "$(typeof(obj))(")))

    for (idx, spec) in enumerate(field_specs)
        field_access = Expr(:(.), :obj, QuoteNode(spec.name))
        push!(body_items, :(print(io, $(field_access))))
        if idx != length(field_specs)
            push!(body_items, :(print(io, ", ")))
        end
    end

    push!(body_items, :(print(io, ")")))

    body_block = Expr(:block, body_items...)
    show_fn = Expr(:function, call_head, body_block)

    docstring = "Optional convenience printer generated by @structmethods; delete this method if you prefer the default Base.show."
    return Expr(:block, docstring, show_fn)
end

macro structmethods(ex)
    ex isa Expr && ex.head == :struct || error("@structmethods must wrap a struct definition")
    is_mutable = ex.args[1]
    struct_name = ex.args[2]
    struct_name isa Symbol || error("@structmethods only supports non-parametric structs")
    body_expr = ex.args[3]
    body_expr isa Expr && body_expr.head == :block || error("@structmethods requires the struct body to be a block")

    fields = FieldSpec[]
    field_stmts = Any[]
    method_specs = MethodSpec[]
    method_stmts = Any[]
    other_stmts = Any[]
    pending_lines = Any[]
    pending_docs = Any[]

    for stmt in body_expr.args
        if _is_line(stmt)
            push!(pending_lines, stmt)
            continue
        end

        if _is_docstring(stmt)
            append!(pending_docs, pending_lines)
            empty!(pending_lines)
            push!(pending_docs, stmt)
            continue
        end

        fieldspec = _extract_field(stmt, struct_name)
        if fieldspec !== nothing
            append!(field_stmts, pending_lines)
            append!(field_stmts, pending_docs)
            empty!(pending_lines)
            empty!(pending_docs)
            push!(field_stmts, fieldspec.expr)
            push!(fields, fieldspec)
            continue
        end

        methodspec = _maybe_method(stmt, struct_name)
        if methodspec !== nothing
            doc_entries = [node for node in pending_docs if !(node isa LineNumberNode)]
            append!(method_stmts, pending_lines)
            append!(method_stmts, pending_docs)
            empty!(pending_lines)
            empty!(pending_docs)
            push!(method_stmts, methodspec.expr)
            push!(method_specs, MethodSpec(methodspec.name, methodspec.expr, doc_entries))
            continue
        end

        append!(other_stmts, pending_lines)
        append!(other_stmts, pending_docs)
        empty!(pending_lines)
        empty!(pending_docs)
        push!(other_stmts, stmt)
    end

    if !isempty(pending_lines)
        append!(other_stmts, pending_lines)
    end
    if !isempty(pending_docs)
        append!(other_stmts, pending_docs)
    end

    isempty(fields) && error("@structmethods requires at least one non-method field")

    method_names = Symbol[]
    const_fields = Any[]
    for method in method_specs
        if method.name in method_names
            error("Duplicate method definition for $(method.name)")
        end
        push!(method_names, method.name)
        append!(const_fields, _make_method_field_entries(method))
    end

    constructor_exprs = _build_constructors(struct_name, fields, method_specs)

    new_body_items = Any[]
    append!(new_body_items, field_stmts)
    append!(new_body_items, const_fields)
    append!(new_body_items, method_stmts)
    append!(new_body_items, other_stmts)
    append!(new_body_items, constructor_exprs)

    new_body = Expr(:block, new_body_items...)
    new_struct = Expr(:struct, is_mutable, struct_name, new_body)
    doc_macro = Expr(:., :Base, QuoteNode(Symbol("@__doc__")))
    doc_struct = Expr(:macrocall, doc_macro, LineNumberNode(0, Symbol("structmethods")), new_struct)

    show_doc_expr = _build_show_definition(struct_name, fields)

    method_doc_items = Any[]
    for method in method_specs
        isempty(method.doc_exprs) && continue
        signature = method.expr.args[1]
        for doc_expr in method.doc_exprs
            signature_copy = Base.deepcopy(signature)
            doc_call = Expr(:macrocall, Symbol("@doc"), LineNumberNode(0, Symbol("structmethods")), doc_expr, signature_copy)
            push!(method_doc_items, doc_call)
        end
    end

    setproperty_expr = _build_setproperty_override(struct_name, method_names)

    result_items = Any[doc_struct, show_doc_expr]
    if setproperty_expr !== nothing
        push!(result_items, setproperty_expr)
    end
    append!(result_items, method_doc_items)
    result_block = Expr(:block, result_items...)

    return esc(result_block)
end
