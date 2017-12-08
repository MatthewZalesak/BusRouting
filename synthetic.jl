# synthetic.jl
# REQUIRES data.jl

#= This is the data type to send to a synthetic data generator. =#
type Request
  demand_count::Int64
  terminal_count::Int64
  permile_rh::Float64
  speed::Float64
  height::Float64
  width::Float64
end

function synthetic_uniform(req::Request)
  @assert req.terminal_count > 1
  println("     Building using seed ", Base.Random.GLOBAL_RNG.seed)
  
  locations = rand(2, req.terminal_count) .* [req.width; req.height]
  
  data = Data(req.terminal_count)
  
  for i = 1:req.terminal_count
    term = Node(locations[1, i], locations[2, i], i)
    push!(data.terminals, term)
    data.arc_children[term] = Node[]
    # data.arc_parents[term] = Node[]
  end
  
  populate_distances(data)
  
  for o = data.terminals
    for d = data.terminals
      data.demands[(o, d)] = 0
    end
  end
  
  # Now we create the demand.
  for i = 1:req.demand_count
    origin, dest = rand(1:req.terminal_count), rand(1:req.terminal_count - 1)
    if dest >= origin
      dest += 1
    end
    origin, dest = data.terminals[origin], data.terminals[dest]
    data.demands[(origin, dest)] += 1
  end
  
  # Create arcs on the graph.
  for i = 1:req.terminal_count
    for j = i + 1:req.terminal_count
      origin = data.terminals[i]
      destination = data.terminals[j]
      push!(data.arc_children[origin], destination)
      push!(data.arc_children[destination], origin)
      arc = Arc(origin, destination, req.speed)
      data.arcs[(origin, destination)] = arc
      data.arcs[(destination, origin)] = arc
    end
  end
  
  for i = 1:req.terminal_count
    for j = 1:req.terminal_count
      data.ridehailcosts[(i, j)] = req.permile_rh * data.distances[(i, j)]
    end
  end
  
  return data
end


type RequestTwoCities
  demand_count::Int64
  terminal_count::Int64
  permile_rh::Float64
  sep_ratio::Float64
  speed::Float64
  height::Float64
  width::Float64
end


#TODO Has not been edited to match new format.
function synthetic_uniform(req::RequestTwoCities)
  println("\t\tBuilding using seed ", Base.Random.GLOBAL_RNG.seed)
  @assert req.terminal_count > 1
  
  locations_city = rand(2, req.terminal_count) .* [req.width; req.height]
  locations_suburb = rand(2, req.terminal_count) .* [req.width; req.height]
  locations_city[1,:] += req.width * req.sep_ratio / 2
  locations_suburb[1,:] -= req.width * req.sep_ratio / 2
  
  data = Data(2 * req.terminal_count)
  
  city_nodes = Node[]   # Odd indices
  suburb_nodes = Node[] # Even indices
 
  # Make nodes.
  for i = 1:req.terminal_count
    index_city = 2*i - 1
    term_city = Node(locations_city[1, i], locations_city[2, i], index_city)
    push!(data.terminals, term_city)
    push!(city_nodes, term_city)
    data.arc_children[term_city] = Node[]
    
    index_suburb = 2*i
    term_suburb = Node(locations_suburb[1, i], locations_suburb[2, i], index_suburb)
    push!(data.terminals, term_suburb)
    push!(suburb_nodes, term_suburb)
    data.arc_children[term_suburb] = Node[]
  end
  
  populate_distances(data)
  
  for o = data.terminals
    for d = data.terminals
      data.demands[(o, d)] = 0
    end
  end
  
  # Now we create the demand.  The demand must ensure that it chooses an origin
  # in the subrub [even index] and a destination in the city [odd index].
  for i = 1:req.demand_count
    origin = rand(suburb_nodes)
    destination = rand(city_nodes)
    data.demands[(origin, destination)] += 1
  end
  
  # Create arcs on the graph.
  for i = 1:length(data.terminals)
    for j = i + 1:length(data.terminals)
      origin = data.terminals[i]
      destination = data.terminals[j]
      push!(data.arc_children[origin], destination)
      push!(data.arc_children[destination], origin)
      arc = Arc(origin, destination, req.speed)
      data.arcs[(origin, destination)] = arc
      data.arcs[(destination, origin)] = arc
    end
  end
  
  # Ridehail costs.
  for i = 1:2*req.terminal_count
    for j = 1:2*req.terminal_count
      data.ridehailcosts[(i, j)] = req.permile_rh * data.distances[(i, j)]
    end
  end
  
  return data
end








function simplest_model()
  data = Data(3)
  for t = 1:6
    push!(data.terminals, Node(0.0, 0.0, t, 1))
    push!(data.terminals, Node(1.0, 0.0, t, 2))
    push!(data.terminals, Node(0.5, sqrt(3) / 2, t, 3))
  end
  for t = 1:5
    for i = 1:3
      o = data.terminals[(t - 1)*3 + i]
      for j = 1:3
        d = data.terminals[t*3 + j]
        arc = Arc(o, d, 1.0)
        data.arcs[(o, d)] = arc
        carway = Carway(o, d)
        data.carways[(o, d)] = carway
      end
    end
  end
  
  data.demands[(data.terminals[3], 1)] = 1.0
  data.demands[(data.terminals[4], 2)] = 1.0
  data.demands[(data.terminals[10], 3)] = 1.0
  
  for i = 1:3
    data.locations[i] = [data.terminals[j] for j in [3*t + i for t in 0:5]]
  end
  
  populate_distances(data)
  
  for i = 1:3
    for j = 1:3
      data.ridehailcosts[(i, j)] = 100.0 # Just some big number so no one uses it.
    end
  end
  
  for t = 1:5
    for i = 1:3
      term = data.terminals[(t - 1) * 3 + i]
      data.arc_children[term] = [data.terminals[j] for j in t*3 + 1:(t + 1)*3]
      data.cw_children[term] = copy(data.arc_children[term])
    end
  end
  
  for t = 2:6
    for i = 1:3
      term = data.terminals[(t - 1)*3 + i]
      data.arc_parents[term] = [data.terminals[j] for j in (t - 2)*3 + 1:(t - 1)*3]
      data.cw_parents[term] = copy(data.arc_parents[term])
    end
  end
  
  for i = 1:3
    term_end = data.terminals[end - i + 1]
    data.arc_children[term_end] = Node[]
    data.cw_children[term_end] = Node[]
    
    term_start = data.terminals[i]
    data.arc_parents[term_start] = Node[]
    data.cw_parents[term_start] = Node[]
  end
  
  # Now specify the parameters that should be used in this function.
  batch_path = 1
  batch_line = 1
  bus_capacity = 1
  bus_fixedcost = 1.0
  cycletimes = [5]
  epsilon = 0.00001
  integer_f = false
  integer_y = false
  lambda = 100.0          # Get people to the destination ASAP.
  search_weighting = 0.5
  terminal_count = 3
  time_resolution = 1.0
  permile_bus = 0.01
  speed = 1.5
  
  param = Parameter(batch_path, batch_line, bus_capacity, bus_fixedcost,
      cycletimes, epsilon, integer_f, integer_y, lambda, search_weighting,
      terminal_count, time_resolution, permile_bus, speed)
  
  return data, param
end









function simplest_model2()
  data = Data(3)
  for t = 1:4
    push!(data.terminals, Node(0.0, 0.0, t, 1))
    push!(data.terminals, Node(1.0, 0.0, t, 2))
    push!(data.terminals, Node(0.5, sqrt(3) / 2, t, 3))
  end
  for t = 1:3
    for i = 1:3
      o = data.terminals[(t - 1)*3 + i]
      for j = 1:3
        d = data.terminals[t*3 + j]
        arc = Arc(o, d, 1.0)
        data.arcs[(o, d)] = arc
        carway = Carway(o, d)
        data.carways[(o, d)] = carway
      end
    end
  end
  
  data.demands[(data.terminals[2], 1)] = 1.0
  data.demands[(data.terminals[2], 1)] = 1.0
  data.demands[(data.terminals[4], 3)] = 3.0
  
  for i = 1:3
    data.locations[i] = [data.terminals[j] for j in [3*t + i for t in 0:3]]
  end
  
  populate_distances(data)
  
  for i = 1:3
    for j = 1:3
      data.ridehailcosts[(i, j)] = 100.0 # Just some big number so no one uses it.
    end
  end
  
  for t = 1:3
    for i = 1:3
      term = data.terminals[(t - 1) * 3 + i]
      data.arc_children[term] = [data.terminals[j] for j in t*3 + 1:(t + 1)*3]
      data.cw_children[term] = copy(data.arc_children[term])
    end
  end
  
  for t = 2:4
    for i = 1:3
      term = data.terminals[(t - 1)*3 + i]
      data.arc_parents[term] = [data.terminals[j] for j in (t - 2)*3 + 1:(t - 1)*3]
      data.cw_parents[term] = copy(data.arc_parents[term])
    end
  end
  
  for i = 1:3
    term_end = data.terminals[end - i + 1]
    data.arc_children[term_end] = Node[]
    data.cw_children[term_end] = Node[]
    
    term_start = data.terminals[i]
    data.arc_parents[term_start] = Node[]
    data.cw_parents[term_start] = Node[]
  end
  
  # Now specify the parameters that should be used in this function.
  batch_path = 1
  batch_line = 1
  bus_capacity = 1
  bus_fixedcost = 1.0
  cycletimes = [3]
  epsilon = 0.00001
  integer_f = false
  integer_y = false
  lambda = 100.0          # Get people to the destination ASAP.
  search_weighting = 0.5
  terminal_count = 3
  time_resolution = 1.0
  permile_bus = 0.01
  speed = 1.5
  
  param = Parameter(batch_path, batch_line, bus_capacity, bus_fixedcost,
      cycletimes, epsilon, integer_f, integer_y, lambda, search_weighting,
      terminal_count, time_resolution, permile_bus, speed)
  
  return data, param
end








function simplest_model3()
  T = 7
  
  data = Data(3)
  for t = 1:T
    push!(data.terminals, Node(0.0, 0.0, t, 1))
    push!(data.terminals, Node(1.0, 0.0, t, 2))
    push!(data.terminals, Node(0.5, sqrt(3) / 2, t, 3))
  end
  for t = 1:(T - 1)
    for i = 1:3
      o = data.terminals[(t - 1)*3 + i]
      for j = 1:3
        d = data.terminals[t*3 + j]
        arc = Arc(o, d, 1.0)
        data.arcs[(o, d)] = arc
        carway = Carway(o, d)
        data.carways[(o, d)] = carway
      end
    end
  end
  
  data.demands[(data.terminals[2], 1)] = 1.0
  data.demands[(data.terminals[3], 1)] = 3.0
  data.demands[(data.terminals[4], 2)] = 3.0
  data.demands[(data.terminals[4], 3)] = 1.0
  data.demands[(data.terminals[8], 1)] = 1.0
  data.demands[(data.terminals[9], 1)] = 1.0
  data.demands[(data.terminals[10], 3)] = 3.0
  data.demands[(data.terminals[11], 3)] = 1.0
  data.demands[(data.terminals[15], 1)] = 3.0
  
  for i = 1:3
    data.locations[i] = [data.terminals[j] for j in [3*t + i for t in 0:(T - 1)]]
  end
  
  populate_distances(data)
  
  for i = 1:3
    for j = 1:3
      data.ridehailcosts[(i, j)] = 50.0 # Just some big number so no one uses it.
    end
  end
  
  for t = 1:(T - 1)
    for i = 1:3
      term = data.terminals[(t - 1) * 3 + i]
      data.arc_children[term] = [data.terminals[j] for j in t*3 + 1:(t + 1)*3]
      data.cw_children[term] = copy(data.arc_children[term])
    end
  end
  
  for t = 2:T
    for i = 1:3
      term = data.terminals[(t - 1)*3 + i]
      data.arc_parents[term] = [data.terminals[j] for j in (t - 2)*3 + 1:(t - 1)*3]
      data.cw_parents[term] = copy(data.arc_parents[term])
    end
  end
  
  for i = 1:3
    term_end = data.terminals[end - i + 1]
    data.arc_children[term_end] = Node[]
    data.cw_children[term_end] = Node[]
    
    term_start = data.terminals[i]
    data.arc_parents[term_start] = Node[]
    data.cw_parents[term_start] = Node[]
  end
  
  # Now specify the parameters that should be used in this function.
  batch_path = 1
  batch_line = 1
  bus_capacity = 1
  bus_fixedcost = 1.0
  cycletimes = [5]
  epsilon = 0.00001
  integer_f = false
  integer_y = false
  lambda = 100.0          # Get people to the destination ASAP.
  search_weighting = 0.5
  terminal_count = 3
  time_resolution = 1.0
  permile_bus = 0.01
  speed = 1.5
  
  param = Parameter(batch_path, batch_line, bus_capacity, bus_fixedcost,
      cycletimes, epsilon, integer_f, integer_y, lambda, search_weighting,
      terminal_count, time_resolution, permile_bus, speed)
  
  return data, param
end














function simplest_model4()
  # Specify the parameters that should be used in this function.
  batch_path = 1
  batch_line = 1
  bus_capacity = 1
  bus_fixedcost = 5.0
  cycletimes = [6]
  epsilon = 0.00001
  integer_f = false
  integer_y = false
  lambda = 100.0          # Get people to the destination ASAP.
  search_weighting = 0.5
  terminal_count = 4
  time_resolution = 1.0
  permile_bus = 0.01
  speed = 3.0
  
  param = Parameter(batch_path, batch_line, bus_capacity, bus_fixedcost,
      cycletimes, epsilon, integer_f, integer_y, lambda, search_weighting,
      terminal_count, time_resolution, permile_bus, speed)
  
  permile_rh = 5.0
  
  a = (0.0, 0.0)
  b = (-.5, 2.0)
  c = (1.0, 2.0)
  d = (0.0, 0.5)
  T = 7
  
  data = Data(4)
  for t = 1:T
    push!(data.terminals, Node(a[1], a[2], t, 1))
    push!(data.terminals, Node(b[1], b[2], t, 2))
    push!(data.terminals, Node(c[1], c[2], t, 3))
    push!(data.terminals, Node(d[1], d[2], t, 4))
  end
  for t = 1:(T - 1)
    for i = 1:4
      o = data.terminals[(t - 1)*4 + i]
      for j = 1:4
        d = data.terminals[t*4 + j]
        arc = Arc(o, d, 1.0)
        data.arcs[(o, d)] = arc
        carway = Carway(o, d)
        data.carways[(o, d)] = carway
      end
    end
  end
  
  #TODO
  data.demands[(data.terminals[1], 2)] = 2.0
  data.demands[(data.terminals[2], 4)] = 1.0
  data.demands[(data.terminals[6], 3)] = 1.0
  data.demands[(data.terminals[6], 4)] = 1.0
  data.demands[(data.terminals[8], 3)] = 1.0
  data.demands[(data.terminals[11], 4)] = 2.0
  data.demands[(data.terminals[12], 1)] = 1.0
  data.demands[(data.terminals[13], 2)] = 1.0
  data.demands[(data.terminals[16], 2)] = 1.0
  data.demands[(data.terminals[16], 3)] = 1.0
  data.demands[(data.terminals[18], 3)] = 2.0
  data.demands[(data.terminals[19], 2)] = 1.0
  data.demands[(data.terminals[22], 1)] = 1.0
  data.demands[(data.terminals[23], 1)] = 1.0
  data.demands[(data.terminals[23], 2)] = 1.0
  
  for i = 1:4
    data.locations[i] = [data.terminals[j] for j in [4*t + i for t in 0:(T - 1)]]
  end
  
  populate_distances(data)
  
  for i = 1:4
    for j = 1:4
      data.ridehailcosts[(i, j)] = permile_rh * data.distances[(i, j)]
    end
  end
  data.ridehailcosts[(4,1)] = 1.0
  
  for t = 1:(T - 1)
    for i = 1:4
      term = data.terminals[(t - 1) * 4 + i]
      data.arc_children[term] = [data.terminals[j] for j in t*4 + 1:(t + 1)*4]
      data.cw_children[term] = copy(data.arc_children[term])
    end
  end
  
  for t = 2:T
    for i = 1:4
      term = data.terminals[(t - 1)*4 + i]
      data.arc_parents[term] = [data.terminals[j] for j in (t - 2)*4 + 1:(t - 1)*4]
      data.cw_parents[term] = copy(data.arc_parents[term])
    end
  end
  
  for i = 1:4
    term_end = data.terminals[end - i + 1]
    data.arc_children[term_end] = Node[]
    data.cw_children[term_end] = Node[]
    
    term_start = data.terminals[i]
    data.arc_parents[term_start] = Node[]
    data.cw_parents[term_start] = Node[]
  end
  return data, param
end
