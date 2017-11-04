# routine.jl

include("data.jl")
include("reports.jl")
include("solver.jl")
include("visual.jl")
include("synthetic.jl")
include("experiments.jl")

# This loads problem settings.  Executes "experiment" defined in "experiments.jl".
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
lfs = LineFinder[]
for c in cycletimes
  push!(lfs, LineFinder(prob, c))
end

println("Running the optimization routine.")
@time autosolve(prob, pf, lfs)


#visual_basic(prob)

