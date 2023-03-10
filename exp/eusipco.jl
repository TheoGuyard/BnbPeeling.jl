include("exp.jl")

function parse_commandline()
    argparse = ArgParseSettings()
    @add_arg_table! argparse begin
        "k"
        arg_type = Int
        required = true
        "m"
        arg_type = Int
        required = true
        "n"
        arg_type = Int
        required = true
        "σ"
        arg_type = Float64
        required = true
        "ρ"
        arg_type = Float64
        required = true
        "τ"
        arg_type = Float64
        required = true
        "γ"
        arg_type = Float64
        required = true
        "solver"
        arg_type = String
        required = true
        "maxtime"
        arg_type = Float64
        required = true
        "--seed"
        arg_type = Int
        required = false
        default = 0
    end
    return parse_args(argparse)
end

function onerun(setup::Dict)

    println("Sanity checks...")
    @assert setup["k"] >= 0
    @assert setup["k"] <= setup["n"]
    @assert setup["m"] >= 0
    @assert setup["n"] >= 0
    @assert setup["σ"] >= 0.0
    @assert setup["ρ"] >= 0.0
    @assert setup["ρ"] <= 1.0
    @assert setup["τ"] >= 0.0
    @assert setup["γ"] >= 1.0
    @assert setup["solver"] in ["cplex", "l0bnb", "sbnb", "sbnbn", "sbnbp"]
    @assert setup["maxtime"] >= 0.0
    @assert setup["seed"] >= 0

    (setup["seed"] > 0) && Random.seed!(setup["seed"])

    println("Generating data...")
    x, A, y = synthetic_data(
        setup["k"],
        setup["m"],
        setup["n"],
        setup["σ"],
        setup["ρ"],
        setup["τ"],
    )

    println("Calibrating λ...")
    x0, λ = calibrate(x, A, y)

    println("Calibrating M...")
    while true
        result = solve_sbnbp(A, y, λ, M, 
            x0          = x0, 
            dualpruning = true,
            l0screening = true, 
            bigmpeeling = true,
            verbosity   = false,
            trace       = false,
            maxtime     = setup["maxtime"],
        )
        if norm(result.x) < M
            M = norm(result.x, Inf)
            break
        end
        M *= 1.1
    end
    
    # The calibration process can be long. You can also set M based on the approximate 
    # solution given by L0Learn. The value of M will not be necessarily valid but is a good 
    # estimate of the "optimal" M value. To do so, comment the above calibration lines and 
    # uncomment the following one.
    # M = norm(x0, Inf)
    
    M *= setup["γ"]

    println("Precompiling...")
    result = solve(setup["solver"], A, y, λ, M, maxtime = 5.0)

    println("Running $(setup["solver"])...")
    result = solve(setup["solver"], A, y, λ, M, maxtime = setup["maxtime"])

    println()
    println(Problem(A, y, λ, M))
    println()
    println("Result")
    println("  Status     : $(result[:termination_status])")
    println("  Objective  : $(round(result[:objective_value], digits=5))")
    println("  Solve time : $(round(result[:solve_time], digits=5)) seconds")
    println("  Node count : $(result[:node_count])")
    println("  Non-zeros  : $(norm(result[:x], 0))")
    println("  Inf-norm x : $(norm(result[:x], Inf))")
    println()

    return nothing
end

setup = parse_commandline()
onerun(setup)
