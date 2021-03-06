function enzyme!(pm)
    ccall((:AddEnzymePass, Enzyme_jll.libEnzyme), Nothing, (LLVM.API.LLVMPassManagerRef,), LLVM.ref(pm))
end

function optimize!(mod::LLVM.Module, entry::LLVM.Function; run_enzyme=true)
    triple = LLVM.triple(mod)
    target = Target(triple)
    tm = TargetMachine(target, triple)
    LLVM.asm_verbosity!(tm, true)

    # everying except unroll, slpvec, loop-vec
    # then finish Julia GC
    ModulePassManager() do pm
        add_library_info!(pm, triple)
        add_transform_info!(pm, tm)

        propagate_julia_addrsp!(pm)
        scoped_no_alias_aa!(pm)
        type_based_alias_analysis!(pm)
        basic_alias_analysis!(pm)
        cfgsimplification!(pm)
        # TODO: DCE (doesn't exist in llvm-c)
        scalar_repl_aggregates!(pm) # SSA variant?
        mem_cpy_opt!(pm)
        always_inliner!(pm)
        alloc_opt!(pm)
        instruction_combining!(pm)
        cfgsimplification!(pm)
        scalar_repl_aggregates!(pm) # SSA variant?
        instruction_combining!(pm)
        jump_threading!(pm)
        instruction_combining!(pm)
        reassociate!(pm)
        early_cse!(pm)
        alloc_opt!(pm)
        loop_idiom!(pm)
        loop_rotate!(pm)
        lower_simdloop!(pm)
        licm!(pm)
        loop_unswitch!(pm)
        instruction_combining!(pm)
        ind_var_simplify!(pm)
        loop_deletion!(pm)
        # SimpleLoopUnroll -- not for Enzyme
        alloc_opt!(pm)
        scalar_repl_aggregates!(pm) # SSA variant?
        instruction_combining!(pm)
        gvn!(pm)
        mem_cpy_opt!(pm)
        sccp!(pm)
        # TODO: Sinking Pass
        # TODO: LLVM <7 InstructionSimplifier
        instruction_combining!(pm)
        jump_threading!(pm)
        dead_store_elimination!(pm)
        alloc_opt!(pm)
        cfgsimplification!(pm)
        loop_idiom!(pm)
        loop_deletion!(pm)
        jump_threading!(pm)
        # SLP_Vectorizer -- not for Enzyme
        aggressive_dce!(pm)
        instruction_combining!(pm)
        # Loop Vectorize -- not for Enzyme
        # InstCombine

        # GC passes
        barrier_noop!(pm)
        lower_exc_handlers!(pm)
        gc_invariant_verifier!(pm, false)
        late_lower_gc_frame!(pm)
        final_lower_gc!(pm)
        # TODO: DCE doesn't exist in llvm-c
        lower_ptls!(pm, #=dump_native=# false)
        cfgsimplification!(pm)
        instruction_combining!(pm) # Extra for Enzyme
        # CombineMulAddPass will run on second pass

        if run_enzyme
            # Enzyme pass
            barrier_noop!(pm)
            enzyme!(pm)
        end
    
        run!(pm, mod)
    end

    return entry
end
