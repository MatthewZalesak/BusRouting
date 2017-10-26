# routine.jl

include("data.jl")
include("solver.jl")
include("synthetic.jl")
include("visual.jl")

dummy = false # This gives Julia one run through so timeing functions are ready.
try   
  routine_init
catch
  dummy = true
end
routine_init = true

demand_count = 1000 # dummy ? 2 : 100 # 10000
terminal_count = 6 # dummy ? 3 : 3 # 8
real_terminal_count = terminal_count
time_resolution = 5.0
timelength = 50 # dummy ? 20 : 50 # 300
permile_rh = 2
sep_ratio = 2
speed = 0.5
height = 2.0
width = 2.0

#req = Request(demand_count, terminal_count, time_resolution, timelength, 
#    permile_rh, speed, height, width)
req = RequestTwoCities(demand_count, terminal_count ,time_resolution, timelength,
    permile_rh, sep_ratio, speed, height, width) ; real_terminal_count = 2*terminal_count

println("Generating synthetic data...")
@time data = synthetic_uniform(req)


batch_path = 1
batch_line = 1
bus_capacity = 20
bus_fixedcost = 10.0 #1
cycletimes = [6] # [12] #[4, 20]
epsilon = 0.00000000001
integer = false
lambda = 0.1
search_weighting = 0.7 #0.5
permile_bus = 1.5 # 0.005

println("Generating parameter object...")
param = Parameter(batch_path, batch_line, bus_capacity, bus_fixedcost, cycletimes, epsilon, integer, lambda, search_weighting, real_terminal_count, time_resolution, permile_bus, speed)

println("Generating problem statement...")
@time prob = Problem(data, param)

println("Running the optimization routine.")
@time linefinders = autosolve(prob)

for (i, y) in enumerate(prob.sol.y)
  if y % 1.0 != 0
    warn("Fractional y variable: ", y, " at ", i)
  end
end

#visual_basic(prob)

