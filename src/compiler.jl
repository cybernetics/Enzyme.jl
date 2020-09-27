module Compiler

import ..Enzyme: Const, Active, Duplicated, DuplicatedNoNeed

using GPUCompiler
using LLVM
using LLVM.Interop

import GPUCompiler: CompilerJob, FunctionSpec, codegen

import Enzyme_jll
import Libdl

const jit = Ref{OrcJIT}()
const tm  = Ref{TargetMachine}()

function __init__()
    LLVM.clopts("-enzyme_preopt=0")

    triple = LLVM.triple()
    target = LLVM.Target(triple=triple)
    tm[] = TargetMachine(target, triple, "", "", LLVM.API.LLVMCodeGenLevelDefault)
    LLVM.asm_verbosity!(tm[], true)
    jit[] = OrcJIT(tm[]) # takes ownership of tm
    atexit() do
        dispose(jit[])
    end
end

# Define EnzymeTarget
using LLVM: Target, TargetMachine

Base.@kwdef struct EnzymeTarget <: AbstractCompilerTarget
end
GPUCompiler.llvm_triple(::EnzymeTarget) = Sys.MACHINE

# GPUCompiler.llvm_datalayout(::EnzymeTarget) =  nothing

function GPUCompiler.llvm_machine(target::EnzymeTarget)
    triple = GPUCompiler.llvm_triple(target)
    t = Target(; triple = triple)
    tm = TargetMachine(t, triple)
    LLVM.asm_verbosity!(tm, true)

    return tm
end

module Runtime
    # the runtime library
    signal_exception() = return
    malloc(sz) = Base.Libc.malloc(sz)
    report_oom(sz) = return
    report_exception(ex) = return
    report_exception_name(ex) = return
    report_exception_frame(idx, func, file, line) = return
end


struct EnzymeCompilerParams <: AbstractCompilerParams end

## job

# TODO: We shouldn't blancket opt-out
GPUCompiler.check_invocation(job::CompilerJob{EnzymeTarget}, entry::LLVM.Function) = nothing

GPUCompiler.runtime_module(target::CompilerJob{EnzymeTarget}) = Runtime
GPUCompiler.isintrinsic(::CompilerJob{EnzymeTarget}, fn::String) = true
GPUCompiler.can_throw(::CompilerJob{EnzymeTarget}) = true

# TODO: encode debug build or not in the compiler job
#       https://github.com/JuliaGPU/CUDAnative.jl/issues/368
GPUCompiler.runtime_slug(job::CompilerJob{EnzymeTarget}) = "enzyme" 

include("compiler/optimize.jl")
include("compiler/cassette.jl")
include("compiler/thunk.jl")
# include("compiler/validation.jl")



end