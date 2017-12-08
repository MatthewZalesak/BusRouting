# routine.jl

include("experiments.jl") # Moved to allow faster startup repetition.
println("Done loading experiments.")
try
  if !skipload
    throw(ErrorException("Time to load data!"))
  end
catch
  include("data.jl") ; println("Done loading data.")
  include("reports.jl") ; println("Done loading reports.")
  include("solver.jl") ; println("Done loading solver.")
  include("visual.jl") ; println("Done loading visual.")
  include("synthetic.jl") ; println("Done loading synthetic.")
  include("research.jl") ; println("Done loading research.")
end
skipload = true

# This loads problem settings.  Executes "experiment" defined in "experiments.jl".

if length(ARGS) > 0
  name = symbol(ARGS[1])
  experiment = eval(name)
end

println("Running experiment: ", name)
eval(experiment)
batch_path = 1

if req_type == :Basic
  real_terminal_count = terminal_count
  req = Request(demand_count, terminal_count, permile_rh, speed, height, width)
elseif req_type == :TwoCities
  real_terminal_count = 2 * terminal_count
  req = RequestTwoCities(demand_count, terminal_count, permile_rh, sep_ratio, 
      speed, height, width)
else
  throw(ErrorException("Unrecognized request type."))
end

println("Generating synthetic data...")
@time data = synthetic_uniform(req)

println("Generating parameter object...")
param = Parameter(batch_path, batch_line, bus_capacity, bus_fixedcost, cycletimes, epsilon, integer_f, integer_y, lambda, search_weighting, real_terminal_count, permile_bus, speed)

println("Generating problem statement...")
@time prob = Problem(data, param)

pf = PathFinder(prob)
lf = LineFinder(prob, maximum(cycletimes))


println("Running the optimization routine.")
@time autosolve(prob, pf, lf)


#visual_basic(prob)

