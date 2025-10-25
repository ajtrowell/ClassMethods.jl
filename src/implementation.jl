
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

function _extract_field(stmt)
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
        lhs isa Expr && lhs.head == :call || return nothing
        lhs.args[1] == struct_name && error("`@structmethods` does not support manually defined inner constructors; remove the constructor or define it outside the struct.")
        method_name = _method_match_from_call(lhs, struct_name)
        if method_name === nothing
            return nothing
        end
        return MethodSpec(method_name, stmt, Any[])
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

function _build_constructors(struct_name::Symbol, field_specs::Vector{FieldSpec}, methods::Vector{MethodSpec})
    signature_args = [spec.signature_arg for spec in field_specs]
    field_names = [spec.name for spec in field_specs]
    closures = [_make_method_closure_expr(method.name) for method in methods]
    new_args = vcat(field_names, closures)

    assign_expr = Expr(:(=), :obj, Expr(:call, :new, new_args...))
    return_expr = :(return obj)
    body = Expr(:block, assign_expr, return_expr)

    positional_signature = Expr(:call, struct_name, signature_args...)
    positional_constructor = Expr(:function, positional_signature, body)

    kw_params = Any[]
    for spec in field_specs
        param_expr = spec.signature_arg
        param_expr = spec.has_default ? Expr(:kw, param_expr, spec.default_expr) : param_expr
        push!(kw_params, param_expr)
    end

    kw_signature = Expr(:call, struct_name, Expr(:parameters, kw_params...))
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

        fieldspec = _extract_field(stmt)
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
    for method in method_specs
        if method.name in method_names
            error("Duplicate method definition for $(method.name)")
        end
        push!(method_names, method.name)
    end

    const_fields = [_make_const_field_expr(name) for name in method_names]
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

    result_items = Any[doc_struct, show_doc_expr]
    append!(result_items, method_doc_items)
    result_block = Expr(:block, result_items...)

    return esc(result_block)
end
