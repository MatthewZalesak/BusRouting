# synthetic.jl
# REQUIRES data.jl

#= This is the data type to send to a synthetic data generator. =#
type Request
  demand_count::Int64
  terminal_count::Int64
  time_resolution::Float64
  timelength::Float64
  permile_rh::Float64
  speed::Float64
  height::Float64
  width::Float64
end

function synthetic_uniform(req::Request)
  @assert req.terminal_count > 1
  println("     Building using seed ", Base.Random.GLOBAL_RNG.seed)
  
  endtime = Int64(div(req.timelength, req.time_resolution))
  locations = rand(2, req.terminal_count) .* [req.width; req.height]
  
  data = Data(req.terminal_count)
 
  
  for t = 1:endtime
    for i = 1:req.terminal_count
      term = Node(locations[1, i], locations[2, i], t, i)
      push!(data.terminals, term)
      push!(data.locations[i], term)
      data.arc_children[term] = Node[]
      data.arc_parents[term] = Node[]
      data.cw_children[term] = Node[]
      data.cw_parents[term] = Node[]
    end
  end
  
  populate_distances(data)
  
  for t = data.terminals
    for j = 1:req.terminal_count
      data.demands[(t, j)] = 0
    end
  end
  
  # Now we create the demand.  The first part is to ensure that all demand is
  # capable of reaching its destination within the final timeframe.
  for i = 1:req.demand_count
    origin = data.locations[rand(1:req.terminal_count)][rand(1:endtime)]
    dest_location = rand(1:req.terminal_count)
    dest = route(origin, data.locations[dest_location], data.distances, 
        req.speed, req.time_resolution)
    while origin.id == dest.id
      origin = data.locations[rand(1:req.terminal_count)][rand(1:endtime)]
      dest_location = rand(1:req.terminal_count)
      dest = route(origin, data.locations[dest_location], data.distances, 
          req.speed, req.time_resolution)
    end
    data.demands[(origin, dest.id)] += 1
  end
  
  for i = 1:req.terminal_count
    for t = 1:endtime
      origin = data.locations[i][t]
      for j = 1:req.terminal_count
        destination = route(origin, data.locations[j], data.distances, 
            req.speed, req.time_resolution)
        if origin != destination
          push!(data.arc_children[origin], destination)
          push!(data.arc_parents[destination], origin)
          push!(data.cw_children[origin], destination)
          push!(data.cw_parents[destination], origin)
          arc = Arc(origin, destination, req.time_resolution)
          data.arcs[(origin, destination)] = arc
          carway = Carway(origin, destination)
          data.carways[(origin, destination)] = carway
        end
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


type RequestTwoCities
  demand_count::Int64
  terminal_count::Int64
  time_resolution::Float64
  timelength::Float64
  permile_rh::Float64
  sep_ratio::Float64
  speed::Float64
  height::Float64
  width::Float64
end


function synthetic_uniform(req::RequestTwoCities)
  println("\t\tBuilding using seed ", Base.Random.GLOBAL_RNG.seed)
  @assert req.terminal_count > 1
  
  endtime = Int64(div(req.timelength, req.time_resolution))
  locations_city = rand(2, req.terminal_count) .* [req.width; req.height]
  locations_suburb = rand(2, req.terminal_count) .* [req.width; req.height]
  locations_city[1,:] += req.width * req.sep_ratio / 2
  locations_suburb[1,:] -= req.width * req.sep_ratio / 2
  
  data = Data(2 * req.terminal_count)
  
  city_nodes = Node[]   # Odd indices
  suburb_nodes = Node[] # Even indices
 
  # Make nodes.
  for t = 1:endtime
    for i = 1:req.terminal_count
      index_city = 2*i - 1
      term_city = Node(locations_city[1, i], locations_city[2, i], t, index_city)
      push!(data.terminals, term_city)
      push!(data.locations[index_city], term_city)
      push!(city_nodes, term_city)
      data.arc_children[term_city] = Node[]
      data.arc_parents[term_city] = Node[]
      data.cw_children[term_city] = Node[]
      data.cw_parents[term_city] = Node[]
      
      index_suburb = 2*i
      term_suburb = Node(locations_suburb[1, i], locations_suburb[2, i], t, index_suburb)
      push!(data.terminals, term_suburb)
      push!(data.locations[index_suburb], term_suburb)
      push!(suburb_nodes, term_suburb)
      data.arc_children[term_suburb] = Node[]
      data.arc_parents[term_suburb] = Node[]
      data.cw_children[term_suburb] = Node[]
      data.cw_parents[term_suburb] = Node[]
    end
  end
  
  populate_distances(data)
  
  # All demand is from suburb to city.
  #for t = suburb_nodes
  #  for j = 1:req.terminal_count
  #    data.demands[(t, 2*j - 1)] = 0
  #  end
  #end
  for t = data.terminals
    for j = 1:2*req.terminal_count
      data.demands[(t, j)] = 0
    end
  end
  
  # Now we create the demand.  The first part is to ensure that all demand is
  # capable of reaching its destination within the final timeframe.  The demand
  # must ensure that it chooses an origin in the subrub [even index] and a
  # destination in the city [odd index].
  for i = 1:req.demand_count
    origin = data.locations[2 * rand(1:req.terminal_count)][rand(1:endtime)]
    dest_location = 2 * rand(1:req.terminal_count) - 1
    dest = route(origin, data.locations[dest_location], data.distances, 
        req.speed, req.time_resolution)
    while origin.id == dest.id
      origin = data.locations[2 * rand(1:req.terminal_count)][rand(1:endtime)]
      dest_location = 2 * rand(1:req.terminal_count) - 1
      dest = route(origin, data.locations[dest_location], data.distances, 
          req.speed, req.time_resolution)
    end
    data.demands[(origin, dest.id)] += 1
  end
  
  for i = 1:2*req.terminal_count
    for t = 1:endtime
      origin = data.locations[i][t]
      for j = 1:2*req.terminal_count
        destination = route(origin, data.locations[j], data.distances, 
            req.speed, req.time_resolution)
        if origin != destination
          push!(data.arc_children[origin], destination)
          push!(data.arc_parents[destination], origin)
          push!(data.cw_children[origin], destination)
          push!(data.cw_parents[destination], origin)
          arc = Arc(origin, destination, req.time_resolution)
          data.arcs[(origin, destination)] = arc
          carway = Carway(origin, destination)
          data.carways[(origin, destination)] = carway
        end
      end
    end
  end
  
  for i = 1:2*req.terminal_count
    for j = 1:2*req.terminal_count
      data.ridehailcosts[(i, j)] = req.permile_rh * data.distances[(i, j)]
    end
  end
  
  return data
end
