# data.jl

import Base.==, Base.display, Base.length, Base.show


immutable Node
  x::Float64
  y::Float64
  id::Int64
end

type ArcData
  time::Float64 # travel time on the arc in actual units.
  distance::Float64
  dualvalue::Float64
end

immutable Arc
  o::Node
  d::Node
  data::ArcData
  
  function Arc(o::Node, d::Node, speed::Float64)
    ad = ArcData(distance(o, d) / speed, distance(o, d), 0)
    return new(o, d, ad)
  end
end

type Data
  arcs::Dict{Tuple{Node,Node},Arc}
  demands::Dict{Tuple{Node,Node},Int64}
  distances::Dict{Tuple{Int64,Int64},Float64}
  arc_children::Dict{Node,Array{Node}}
  ridehailcosts::Dict{Tuple{Int64,Int64},Float64}
  terminals::Array{Node}
  
  #= Generic, blank initialization. =#
  function Data(terminal_count::Int64)
    arcs = Dict{Tuple{Node,Node},Arc}()
    demands = Dict{Tuple{Node,Node},Int64}()
    distances = Dict{Tuple{Int64,Int64},Float64}()
    arc_children = Dict{Node,Array{Node}}() 
    ridehailcosts = Dict{Tuple{Int64,Int64},Float64}()
    terminals = Node[]    
    return new(arcs, demands, distances, arc_children,
        ridehailcosts, terminals)
  end
end

type Parameter
  batch_path::Int64
  batch_line::Int64
  bus_capacity::Int64
  bus_fixedcost::Float64
  cycletimes::Array{Int64}
  epsilon::Float64
  integer_f::Bool
  integer_y::Bool
  lambda::Float64
  search_weighting::Float64
  terminal_count::Int64
  permile_bus::Float64
  speed::Float64
end


type Line
  line::Array{Arc}
  cost::Float64
  index::Int64
end

immutable PathRoute
  pickup::Union{Void,Tuple{Node,Node}}
  buses::Array{Arc}
  dropoff::Union{Void,Tuple{Node,Node}}
end


type Path
  route::PathRoute
  independentcost::Float64
  taketime::Float64           # Units do not include time_resolution.
  index::Int64
end
function od(p::Path)
  return od(p.route)
end

type Computed
  lines::Array{Line}
  paths::Array{Path}
  lookup_lines::Dict{Arc,Array{Int64}}
  lookup_paths::Dict{Arc,Array{Int64}}
  ST::Dict{Tuple{Node,Node},Array{Int64}}
  linecosts::Array{Float64}
  pathcosts::Array{Float64}
  
  
  function Computed(data::Data, param::Parameter)
    lines = Line[]
    paths = Path[]
    lookup_lines = Dict{Arc,Array{Int64}}()
    lookup_paths = Dict{Arc,Array{Int64}}()
    ST = Dict{Tuple{Node,Node},Array{Int64}}()
    linecosts = Float64[]
    pathcosts = Float64[]
    
    for a in values(data.arcs)
      lookup_lines[a] = Int64[]
      lookup_paths[a] = Int64[]
    end
    for o in data.terminals
      for d in data.terminals
        key = (o, d)
        ST[key] = Int64[]
      end
    end
    for ((origin, destination), value) in data.demands
      if value > 0
        pathroute = PathRoute((origin, destination), Arc[], nothing)
        independentcost = data.ridehailcosts[(origin.id, destination.id)]
        taketime = data.distances[(origin.id, destination.id)] / param.speed
        index = length(paths) + 1
        path = Path(pathroute, independentcost, taketime, index)
        
        push!(paths, path)
        push!(ST[(origin, destination)], index)
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
    comp = Computed(data, param)
    sol = Solution(Float64[], Float64[], Float64[], Float64[], Inf)
    return new(comp, data, param, sol)
  end
end


#= General useful functions. =#

function cost(path::Path, prob::Problem)
  return prob.param.lambda * path.taketime + path.independentcost
end

function cost(prob::Problem)
  return sum(prob.comp.pathcosts .* prob.sol.y) + sum(prob.comp.linecosts .* prob.sol.f)
end

function distance(a::Node, b::Node)
  return sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end

function ==(a::PathRoute, b::PathRoute)
  if a.dropoff != b.dropoff || a.pickup != b.pickup ||
      length(a.buses) != length(b.buses)
    return false
  end
  for (i, j) in zip(a.buses, b.buses)
    i == j || return false
  end
  return true
end

function length(line::Line)
  return Int64(length(line.line) / 2)
end

function od(pr::PathRoute)
  origin = nothing
  if pr.pickup != nothing
    if pr.pickup.d == pr.buses[1].o || pr.pickup.d == pr.buses[1].d
      origin = pr.pickup.o
    else
      origin = pr.pickup.d
    end
  else
    origin # TODO
  end
  origin = (pr.pickup != nothing) ? pr.pickup.o : pr.buses[1].o
  destination = nothing::Union{Void,Node}
  if pr.dropoff != nothing
    destination = pr.dropoff.d
  elseif length(pr.buses) > 0
    destination = pr.buses[end].d
  else
    destination = pr.pickup[end].d
  end
  return origin, destination
end

function populate_distances(data::Data)
  for (i, o) in enumerate(data.terminals)
    for (j, d) in enumerate(data.terminals)
      data.distances[(i, j)] = distance(o, d)
    end
  end
end

function restorepathcost(prob::Problem)
  for (i, p) in enumerate(prob.comp.paths)
    prob.comp.pathcosts[i] = cost(p, prob)
  end
end

function restorelinecost(prob::Problem)
  for (i, l) in enumerate(prob.comp.lines)
    prob.comp.linecosts[i] = l.cost
  end
end

function restore(prob::Problem)
  restorepathcost(prob)
  restorelinecost(prob)
end
