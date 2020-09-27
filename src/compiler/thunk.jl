struct Thunk{f, RT, TT}
    ptr::Ptr{Cvoid}
end

# work around https://github.com/JuliaLang/julia/issues/37778
__normalize(::Type{Base.RefValue{T}}) where T = Ref{T}
__normalize(::Type{Base.RefArray{T}}) where T = Ref{T}
__normalize(T::DataType) = T

@generated function (thunk::Thunk{f, RT, TT})(args...) where {f, RT, TT}
    _args = (:(args[$i]) for i in 1:length(args))
    nargs = map(__normalize, args)
    quote
        ccall(thunk.ptr, $RT, ($(nargs...),), $(_args...))
    end
end

function thunk(f::F,tt::TT=Tuple{}) where {F<:Core.Function, TT<:Type}
    primal, adjoint, rt = fspec(f, tt)

    # We need to use adjoint as the key
    GPUCompiler.cached_compilation(_thunk, adjoint, primal=primal, rt=rt)::Thunk{F,rt,tt}
end

# actual compilation
function _thunk(adjoint::FunctionSpec; primal, rt)
    target = Compiler.EnzymeTarget()
    params = Compiler.EnzymeCompilerParams()
    job    = Compiler.CompilerJob(target, primal, params)

    # Codegen the primal function and all its dependency in one module
    mod, primalf = Compiler.codegen(:llvm, job, optimize=false, #= validate=false =#)

    # Generate the wrapper, named `enzyme_entry`
    llvmf = wrapper!(mod, primalf, adjoint, rt)

    LLVM.strip_debuginfo!(mod)    
    # Run pipeline and Enzyme pass
    optimize!(mod, llvmf)

    # Now invoke the JIT
    jitted_mod = compile(jit[], mod)
    ptr = addressin(jit[], jitted_mod, "enzyme_entry")

    return Thunk{typeof(adjoint.f), rt, adjoint.tt}(ptr)
end


