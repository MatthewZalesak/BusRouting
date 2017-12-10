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

function synthetic_uniform(req::Request, prob::Float64)
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
      if rand() < prob
        origin = data.terminals[i]
        destination = data.terminals[j]
        push!(data.arc_children[origin], destination)
        push!(data.arc_children[destination], origin)
        arc = Arc(origin, destination, req.speed)
        data.arcs[(origin, destination)] = arc
        arc = Arc(destination, origin, req.speed)
        data.arcs[(destination, origin)] = arc
      end
    end
  end
  
  for i = 1:req.terminal_count
    for j = 1:req.terminal_count
      data.ridehailcosts[(i, j)] = req.permile_rh * data.distances[(i, j)]
    end
  end
  
  return data
end

function synthetic_uniform(req::Request)
  return synthetic_uniform(req, 1.0)
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
function synthetic_uniform(req::RequestTwoCities, prob::Float64)
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
      if rand() < prob
        origin = data.terminals[i]
        destination = data.terminals[j]
        push!(data.arc_children[origin], destination)
        push!(data.arc_children[destination], origin)
        arc = Arc(origin, destination, req.speed)
        data.arcs[(origin, destination)] = arc
        arc = Arc(destination, origin, req.speed)
        data.arcs[(destination, origin)] = arc
      end
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
