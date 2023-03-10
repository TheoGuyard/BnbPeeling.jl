"""
    CoordinateDescent <: AbstractBoundingSolver

Coordinate-descent solver for the bounding problems.
"""
Base.@kwdef struct CoordinateDescent <: AbstractBoundingSolver
    tolgap::Float64 = 1e-8
    maxiter::Int = 10_000
end

function bound!(
    solver::CoordinateDescent,
    prob::Problem,
    bnb::BnB,
    node::Node,
    options::BnbParams,
    bounding_type::BoundingType,
)

    # ----- Initialization ----- #

    # Problem data
    A = prob.A
    y = prob.y
    λ = prob.λ
    m = prob.m
    n = prob.n
    a = prob.a

    # Recover node informations
    if bounding_type == LOWER
        S0 = node.S0
        S1 = node.S1
        Sb = node.Sb
        Mpos = node.Mpos
        Mneg = node.Mneg
        x = node.x
        w = node.w
        u = node.u
        v = Vector(undef, n)
        r = Vector(undef, n)
        q = Vector(undef, n)
    elseif bounding_type == UPPER
        S0 = copy(node.S0 .| node.Sb)
        S1 = copy(node.S1)
        Sb = falses(n)
        Mpos = node.Mpos
        Mneg = node.Mneg
        x = zeros(n)
        x[S1] = copy(node.x[S1])
        w = A[:, S1] * x[S1]
        u = y - w
        v = Vector(undef, n)
        r = Vector(undef, n)
        q = Vector(undef, n)
    else
        error("Unknown bounding type $bounding_type")
    end

    # Support configuration
    Sb0 = falses(n)
    Sbi = copy(Sb)
    Sbb = falses(n)
    S1i = copy(S1)
    S1b = falses(n)

    # BnB, options and solver values
    ub = bnb.ub
    maxtime = options.maxtime
    dualpruning = options.dualpruning
    l0screening = options.l0screening
    l1screening = options.l1screening
    bigmpeeling = options.bigmpeeling
    tolgap = solver.tolgap
    maxiter = solver.maxiter

    # Objectives
    pv = Inf
    dv = -Inf
    gap = Inf

    # ----- Main loop ----- #

    it = 0
    while true

        it += 1

        # ----- Coordinate descent loop ----- #

        idx = (Sbi .| Sbb .| S1i .| S1b)
        for i in shuffle(findall(idx))
            ai = A[:, i]
            xi = x[i]
            ci = xi + (ai' * u) / a[i]
            if Sb[i]
                if (λ / a[i]) / Mneg[i] <= ci <= (λ / a[i]) / Mpos[i]
                    x[i] = 0.0
                elseif ci > (λ / a[i]) / Mpos[i]
                    x[i] = clamp(ci - (λ / a[i]) / Mpos[i], 0, Mpos[i])
                elseif ci < (λ / a[i]) / Mneg[i]
                    x[i] = clamp(ci - (λ / a[i]) / Mneg[i], Mneg[i], 0)
                end
            else
                x[i] = clamp(ci, Mneg[i], Mpos[i])
            end
            if x[i] != xi
                axpy!(x[i] - xi, ai, w)
                copy!(u, y - w)
            end
        end

        # ----- Gap computation ----- #

        Sbpos = (Sbi .| Sbb) .& (0.0 .< x .<= Mpos)
        Sbneg = (Sbi .| Sbb) .& (0.0 .> x .>= Mneg)
        v[idx] = A[:, idx]' * u
        q[idx] = (
            Mpos[idx] .* max.(v[idx] ./ λ, 0.0) + Mneg[idx] .* min.(v[idx] ./ λ, 0.0) .-
            1.0
        )

        # Primal value
        fval = 0.5 * (u' * u)
        gval = 0.0
        for i in findall(idx)
            if Sbpos[i]
                gval += max(x[i], 0.0) / Mpos[i]
            elseif Sbneg[i]
                gval += min(x[i], 0.0) / Mneg[i]
            elseif S1[i]
                gval += 1.0
            end
        end
        pv = fval + λ * gval

        # Dual value
        cfval = 0.5 * (u' * u) - u' * y
        cgval = 0.0
        for i in findall(idx)
            cgval += Sb[i] ? max(q[i], 0.0) : q[i]
        end
        dv = -cfval - λ * cgval

        # Gap
        gap = abs(pv - dv)

        # ----- Stopping criterion ----- #

        if gap < tolgap
            break
        elseif it > maxiter
            # @warn "maxiter reached, last gap : $(gap)"
            break
        elseif elapsed_time(bnb) >= maxtime
            # @warn "maxtime reached, last gap : $(gap)"
            break
        end

        # --- Accelerations --- #

        if bounding_type == LOWER
            dualpruning && (dv >= ub) && break
            (l0screening | bigmpeeling) && l0screening!(
                A,
                y,
                λ,
                Mpos,
                Mneg,
                x,
                w,
                u,
                q,
                ub,
                dv,
                S0,
                S1,
                Sb,
                Sbi,
                Sbb,
                S1i,
            )
            l1screening && l1screening!(A, y, λ, Mpos, Mneg, x, w, u, v, gap, Sb0, Sbi, Sbb)
            bigmpeeling &&
                bigmpeeling!(A, y, λ, Mpos, Mneg, x, w, u, v, q, ub, dv, S0, Sb, Sbi, Sbb)
        end
    end



    # ----- Post-processing ----- #

    if bounding_type == LOWER
        node.lb = dv
    elseif bounding_type == UPPER
        node.ub = pv
        node.x_ub = copy(x)
    else
        error("Unknown bounding type $bounding_type")
    end

    return nothing
end
