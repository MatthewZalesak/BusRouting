# data.jl

import Base.==, Base.display, Base.show


immutable Node
  x::Float64
  y::Float64
  t::Int64
  id::Int64
  
  function Node(x::Float64, y::Float64, t::Int64, i::Int64)
    return new(x, y, t, i)
  end
  function Node(n::Node, t::Float64)
    return new(n.x, n.y, t, n.id)
  end
end

type ArcData
  time::Float64
  dualvalue::Float64
end

immutable Arc
  o::Node
  d::Node
  data::ArcData
  
  function Arc(o::Node, d::Node, time_resolution::Float64)
    ad = ArcData((d.t - o.t) * time_resolution, 0)
    return new(o, d, ad)
  end
end

immutable Carway
  o::Node
  d::Node
end

type Data
  arcs::Dict{Tuple{Node,Node},Arc}
  carways::Dict{Tuple{Node,Node},Carway}
  demands::Dict{Tuple{Node,Int64},Int64}
  distances::Dict{Tuple{Int64,Int64},Float64}
  locations::Array{Array{Node}}
  arc_children::Dict{Node,Array{Node}}
  arc_parents::Dict{Node,Array{Node}}
  cw_children::Dict{Node,Array{Node}}
  cw_parents::Dict{Node,Array{Node}}
  ridehailcosts::Dict{Tuple{Int64,Int64},Float64}
  terminals::Array{Node}
  
  #= Generic, blank initialization. =#
  function Data(terminal_count::Int64)
    arcs = Dict{Tuple{Node,Node},Arc}()
    carways = Dict{Tuple{Node,Node},Carway}()
    demands = Dict{Tuple{Node,Int64},Int64}()
    distances = Dict{Tuple{Int64,Int64},Float64}()
    locations = Array{Array{Node}}(terminal_count)
    for i = 1:terminal_count
      locations[i] = Node[]
    end
    arc_children = Dict{Node,Array{Node}}()
    arc_parents = Dict{Node,Array{Node}}()
    cw_children = Dict{Node,Array{Node}}()
    cw_parents = Dict{Node,Array{Node}}()    
    ridehailcosts = Dict{Tuple{Int64,Int64},Float64}()
    terminals = Node[]    
    return new(arcs, carways, demands, distances, locations, arc_children, 
        arc_parents, cw_children, cw_parents, ridehailcosts, terminals)
  end
end

type Parameter
  batch_path::Int64
  batch_line::Int64
  bus_capacity::Int64
  bus_fixedcost::Float64
  cycletimes::Array{Int64}
  epsilon::Float64
  integer::Bool
  lambda::Float64
  search_weighting::Float64
  terminal_count::Int64
  time_resolution::Float64
  permile_bus::Float64
  speed::Float64
end

function distance(a::Node, b::Node)
  return sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end

function populate_distances(data::Data)
  for i = 1:length(data.locations)
    for j = 1:length(data.locations)
      data.distances[(i, j)] = distance(data.locations[i][1], data.locations[j][1])
    end
  end
end

#= This function finds a destination node.  If it returns o, there was an error. =#
function route(o::Node, d::Array{Node}, dists::Dict{Tuple{Int64,Int64},Float64},
    speed::Float64, time_resolution::Float64)
  if o.id == d[1].id
    if o.t + 1 <= length(d)
      return d[o.t + 1]
    else
      return o
    end
  end
  timetake = dists[(o.id, d[1].id)] / speed
  index = o.t + Int64(ceil(timetake / time_resolution))
  if index <= length(d)
    return d[index]
  else
    return o
  end
end
function route(pair::Tuple{Node,Int64}, data::Data, param::Parameter)
  return route(pair[1], data.locations[pair[2]], data.distances, param.speed, 
      param.time_resolution)
end

type Line
  line::Array{Arc}
  cost::Float64
  cyclelength::Int64
  index::Int64
end

immutable PathRoute
  pickup::Array{Carway}
  buses::Array{Arc}
  dropoff::Union{Void,Carway}
end
function ==(a::PathRoute, b::PathRoute)
  if a.dropoff != b.dropoff || length(a.pickup) != length(b.pickup) || length(a.buses) != length(b.buses)
    return false
  end
  for (i, j) in zip(a.pickup, b.pickup)
    i == j || return false
  end
  for (i, j) in zip(a.buses, b.buses)
    i == j || return false
  end
  return true
end

type Path
  route::PathRoute
  independentcost::Float64
  taketime::Float64           # Units do not include time_resolution.
  index::Int64
end

type Computed
  lines::Array{Line}
  paths::Array{Path}
  lookup_lines::Dict{Arc,Array{Int64}}
  lookup_paths::Dict{Arc,Array{Int64}}
  ST::Dict{Tuple{Node,Int64},Array{Int64}}
  linecosts::Array{Float64}
  pathcosts::Array{Float64}
  
  
  function Computed(data::Data, param::Parameter)
    lines = Line[]
    paths = Path[]
    lookup_lines = Dict{Arc,Array{Int64}}()
    lookup_paths = Dict{Arc,Array{Int64}}()
    ST = Dict{Tuple{Node,Int64},Array{Int64}}()
    linecosts = Float64[]
    pathcosts = Float64[]
    
    for a in values(data.arcs)
      lookup_lines[a] = Int64[]
      lookup_paths[a] = Int64[]
    end
    for t in data.terminals
      for i = 1:param.terminal_count
        key = (t, i)
        ST[key] = Int64[]
      end
    end
    for (key, value) in data.demands
      if value > 0
        destination = route(key, data, param)
        
        pathroute = PathRoute([data.carways[(key[1], destination)]], Arc[], nothing)
        independentcost = data.ridehailcosts[(key[1].id, destination.id)]
        taketime = param.time_resolution * (destination.t - key[1].t)
        index = length(paths) + 1
        path = Path(pathroute, independentcost, taketime, index)
        
        push!(paths, path)
        push!(ST[key], index)
        push!(pathcosts, independentcost + param.lambda * taketime)
      end
    end
    
    return new(lines, paths, lookup_lines, lookup_paths, ST, linecosts, pathcosts)
  end
end

type Solution
  y::Array{Float64}
  f::Array{Float64}
  dualdemand::Array{Float64}
  dualarc::Array{Float64}
  objective::Float64
end

type Problem
  comp::Computed
  data::Data
  param::Parameter
  sol::Solution
  
  function Problem(data::Data, param::Parameter)
    sort!(data.terminals, by=x -> (x.t, x.id))
    comp = Computed(data, param)
    sol = Solution(Float64[], Float64[], Float64[], Float64[], Inf)
    return new(comp, data, param, sol)
  end
end



### SPECIAL FUNCTION FOR VISUALIZING VARIABLES. ###

function display(n::Node)
  print("Node(", n.t, ", ", n.id, ")")
end

function display(ad::ArcData)
  print("ArcData(", ad.time, ", ", round(ad.dualvalue, 6), ")")
end

function display(a::Arc)
  print("Arc(")
  display(a.o)
  print(", ")
  display(a.d)
  print(", ")
  display(a.data)
  print(")")
end

function display(c::Carway)
  print("Carway(")
  display(c.o)
  print(", ")
  display(c.d)
  print(")")
end

function display(pr::PathRoute)
  print("PathRoute(pickups=> ")
  for p in pr.pickup
    display(p)
    print(", ")
  end
  print("buses=> ")
  for b in pr.buses
    display(b)
    print(", ")
  end
  print("dropoff=> ")
  if pr.dropoff != nothing
    display(pr.dropoff)
  end
  print(")")
end
function show(pr::PathRoute)
  display(pf)
end

function display(p::Path)
  print("Path(ID ", p.index, ", ")
  display(p.route)
  print(", duration: ", p.taketime, ")")
end
function show(p::Path)
  display(p)
end