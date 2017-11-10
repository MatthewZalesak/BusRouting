# routine.jl

include("experiments.jl") # Moved to allow faster startup repetition.
try
  if !skipload
    throw(ErrorException("Time to load data!"))
  end
catch
  include("data.jl")
  include("reports.jl")
  include("solver.jl")
  include("deepsolver.jl")
  include("visual.jl") # Removed for loading time issures.
  include("synthetic.jl")
  include("research.jl")
end
skipload = true

# This loads problem settings.  Executes "experiment" defined in "experiments.jl".

if length(ARGS) > 0
  name = symbol(ARGS[1])
  experiment = eval(name)
end

println("Running experiment: ", name)
eval(experiment)

if req_type == :Basic
  real_terminal_count = terminal_count
  req = Request(demand_count, terminal_count, time_resolution, timelength, 
      permile_rh, speed, height, width)
elseif req_type == :TwoCities
  real_terminal_count = 2 * terminal_count
  req = RequestTwoCities(demand_count, terminal_count ,time_resolution, timelength,
      permile_rh, sep_ratio, speed, height, width)
else
  throw(ErrorException("Unrecognized request type."))
end

println("Generating synthetic data...")
@time data = synthetic_uniform(req)

println("Generating parameter object...")
param = Parameter(batch_path, batch_line, bus_capacity, bus_fixedcost, cycletimes, epsilon, integer_f, integer_y, lambda, search_weighting, real_terminal_count, time_resolution, permile_bus, speed)

println("Generating problem statement...")
@time prob = Problem(data, param)

pf = PathFinder(prob)
lfs = [LineFinder(prob, c) for c in cycletimes]

println("Running the optimization routine.")
@time autosolve(prob, pf, lfs)

sol = deepcopy(prob.sol)

println("Attempting rounded solution...")
runlp(prob, mod_round)
state_solution(prob)
println("Cost: ", cost(prob))
println("Ratio: ", cost(prob) / sol.objective)
println("Seed:  ", Base.Random.GLOBAL_RNG.seed)

if has_fractional(sol)
  throw(ErrorException("Yippy!"))
end


#visual_basic(prob)

