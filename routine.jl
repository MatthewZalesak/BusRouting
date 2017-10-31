# routine.jl

include("data.jl")
include("solver.jl")
include("synthetic.jl")
include("visual.jl")

srand(UInt32[0x18806502, 0xdf92f559, 0x537b84bd, 0xf575a265])

warmup = false # This gives Julia one run through so timing functions are ready.
try   
  routine_init
catch
  warmup = true
end
routine_init = true

demand_count = 10000 # warmup ? 2 : 100 # 10000
terminal_count = 6 # warmup ? 3 : 3 # 8
real_terminal_count = terminal_count
time_resolution = 5.0
timelength = 120 # warmup ? 20 : 50 # 300
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


batch_path = 5
batch_line = 5
bus_capacity = 20
bus_fixedcost = 200.0 #1
cycletimes = [6] # [12] #[4, 20]
epsilon = 0.000001
integer_f = false
integer_y = false
lambda = 1.0
search_weighting = 0.7 #0.5
permile_bus = 1.0 # 0.005

println("Generating parameter object...")
param = Parameter(batch_path, batch_line, bus_capacity, bus_fixedcost, cycletimes, epsilon, integer_f, integer_y, lambda, search_weighting, real_terminal_count, time_resolution, permile_bus, speed)

println("Generating problem statement...")
@time prob = Problem(data, param)

println("Running the optimization routine.")
@time linefinders = autosolve(prob)


#visual_basic(prob)

